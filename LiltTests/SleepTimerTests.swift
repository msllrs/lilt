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

    @Test func theControlsMenuOffersItsTimes() async throws {
        let player = try #require(AppDelegate.shared?.player)
        defer { player.setSleepTimer(nil) }
        func timer() -> NSMenu? {
            let controls = NSApp.mainMenu?.items.first { $0.title == "Controls" }?.submenu
            guard let controls else { return nil }
            controls.delegate?.menuNeedsUpdate?(controls)
            return controls.items.first { $0.title == "Sleep Timer" }?.submenu
        }
        player.setSleepTimer(nil)
        for _ in 0..<5 { try await Task.sleep(for: .milliseconds(20)) }
        let menu = try #require(timer(), "Controls ▸ Sleep Timer")
        #expect(menu.items.map(\.title) == ["Off", "15 Minutes", "30 Minutes", "1 Hour"])
        #expect(menu.items.map(\.state) == [.on, .off, .off, .off])

        player.setSleepTimer(.seconds(30 * 60))
        for _ in 0..<5 { try await Task.sleep(for: .milliseconds(20)) }
        #expect(try #require(timer()).items.map(\.state) == [.off, .off, .on, .off])
    }
}
