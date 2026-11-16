import AppKit
import Testing
@testable import Lilt

/// Controls ▸ Sleep Timer: the music pauses once the time chosen is up, for falling asleep to
/// an album or for stopping before a call without watching the clock. Off, or another time
/// chosen, and the one before never fires.
@MainActor
struct SleepTimerTests {
    private let songs = [Track(id: "schism", title: "Schism", artist: "Tool"), Track(id: "parabola", title: "Parabola", artist: "Tool")]

    @Test func theMusicPausesWhenTheTimeIsUp() async throws {
        try await withFakePlayer(songs, gapless: false) { player, fakes in
            fakes.startPlaying(player)
            player.setSleepTimer(.milliseconds(100))
            #expect(player.sleepTimer == .milliseconds(100))
            try await Task.sleep(for: .milliseconds(400))
            #expect(!player.isPlaying)
            #expect(fakes.first.calls.last == "pause")
            #expect(player.sleepTimer == nil, "a timer that has fired is spent")
        }
    }

    @Test func turnedOffTheMusicPlaysOn() async throws {
        try await withFakePlayer(songs, gapless: false) { player, fakes in
            fakes.startPlaying(player)
            player.setSleepTimer(.milliseconds(100))
            player.setSleepTimer(nil)
            try await Task.sleep(for: .milliseconds(400))
            #expect(player.isPlaying)
            #expect(!fakes.first.calls.contains("pause"))
        }
    }

    @Test func anotherTimeReplacesTheFirst() async throws {
        try await withFakePlayer(songs, gapless: false) { player, fakes in
            fakes.startPlaying(player)
            player.setSleepTimer(.milliseconds(100))
            player.setSleepTimer(.seconds(30))
            try await Task.sleep(for: .milliseconds(400))
            #expect(player.isPlaying, "the first time was replaced, not added to")
            #expect(player.sleepTimer == .seconds(30))
            player.setSleepTimer(nil)
        }
    }

    // MARK: Across a relaunch

    /// A timer set before quitting still pauses at the time it was set for; the menu ticks the
    /// length it was set to.
    @Test func aRunningTimerSurvivesARelaunch() async throws {
        let defaults = try #require(UserDefaults(suiteName: "SleepTimerTests.\(UUID().uuidString)"))
        try await withFakePlayer(songs, gapless: false) { player, fakes in
            fakes.startPlaying(player)
            player.setSleepTimer(.seconds(30 * 60))
            SleepTimerStore.save(player, to: defaults)
            player.setSleepTimer(nil)

            let now = Date.now.addingTimeInterval(29 * 60 + 59.8)
            SleepTimerStore.restore(into: player, from: defaults, now: now)
            #expect(player.sleepTimer == .seconds(30 * 60), "the menu still ticks 30 Minutes")
            try await Task.sleep(for: .milliseconds(600))
            #expect(!player.isPlaying, "it pauses when the time it was set for comes")
        }
    }

    @Test func aTimerThatRanOutWhileQuitIsForgotten() async throws {
        let defaults = try #require(UserDefaults(suiteName: "SleepTimerTests.\(UUID().uuidString)"))
        try await withFakePlayer(songs, gapless: false) { player, fakes in
            fakes.startPlaying(player)
            player.setSleepTimer(.seconds(15 * 60))
            SleepTimerStore.save(player, to: defaults)
            player.setSleepTimer(nil)

            SleepTimerStore.restore(into: player, from: defaults, now: .now.addingTimeInterval(16 * 60))
            #expect(player.sleepTimer == nil)
            #expect(player.isPlaying, "nothing pauses a relaunch hours later")
            #expect(defaults.object(forKey: SleepTimerStore.endsKey) == nil, "and the spent timer is cleared")
        }
    }

    @Test func turningItOffClearsTheSavedTimer() async throws {
        let defaults = try #require(UserDefaults(suiteName: "SleepTimerTests.\(UUID().uuidString)"))
        try await withFakePlayer(songs, gapless: false) { player, _ in
            player.setSleepTimer(.seconds(60 * 60))
            SleepTimerStore.save(player, to: defaults)
            player.setSleepTimer(nil)
            SleepTimerStore.save(player, to: defaults)
            #expect(defaults.object(forKey: SleepTimerStore.endsKey) == nil)
        }
    }

    @Test func theControlsMenuOffersItsTimes() async throws {
        let player = try #require(AppDelegate.shared?.player)
        defer { player.setSleepTimer(nil) }
        func timer() -> NSMenu? {
            let controls = NSApp.mainMenu?.items.first { $0.title == "Controls" }?.submenu
            guard let controls else { return nil }
            controls.delegate?.menuNeedsUpdate?(controls)
            return controls.items.first { $0.title == "Sleep Timer" }?.submenu
        }
        /// The submenu's items without the separators the inline picker draws around itself.
        func items(_ menu: NSMenu) -> [NSMenuItem] { menu.items.filter { !$0.isSeparatorItem } }
        player.setSleepTimer(nil)
        for _ in 0..<5 { try await Task.sleep(for: .milliseconds(20)) }
        let menu = try #require(timer(), "Controls ▸ Sleep Timer")
        #expect(items(menu).map(\.title) == ["Off", "15 Minutes", "30 Minutes", "1 Hour"])
        #expect(items(menu).map(\.state) == [.on, .off, .off, .off])

        player.setSleepTimer(.seconds(30 * 60))
        for _ in 0..<5 { try await Task.sleep(for: .milliseconds(20)) }
        let running = try #require(timer())
        #expect(items(running).prefix(4).map(\.state) == [.off, .off, .on, .off])
        let ends = try #require(player.sleepEnds)
        #expect(items(running).last?.title == "Pauses at \(ends.formatted(date: .omitted, time: .shortened))", "the menu says when")
    }
}
