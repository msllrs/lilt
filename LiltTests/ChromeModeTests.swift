import Foundation
import Testing
import WebKit
@testable import Lilt

/// Chrome mode (experimental) is native queue mode with the player page presenting Chrome's
/// user agent, so YouTube's player turns on its own gapless. These check that only the player
/// page gets that user agent, that switching in and out reloads the song where it was, that a
/// playback error loads the song again and two in a row put the page back on Safari's user
/// agent for the session, and that a same-stream move is adopted with its times shown from
/// where the new song starts.
@MainActor
struct ChromeModeTests {
    private func song(_ id: String) -> Track { Track(id: id, title: id, artist: "Tool") }
    private var lateralus: [Track] { ["grudge", "eon", "patient", "mantra"].map(song) }

    private func withPlayer(
        _ queue: [Track], gapless: PlayerService.GaplessMode = .chromeQueue,
        _ body: (PlayerService, FakePlayers) async throws -> Void
    ) async throws {
        try await withFakePlayer(queue, gapless: gapless, body)
    }

    private func confirm(_ fakes: FakePlayers, _ id: String) {
        fakes.first.onEvent?(.queuedNext(videoId: id, ok: true, reason: "queue-readback-confirmed"))
    }

    private func fail(_ fakes: FakePlayers, _ id: String?) {
        fakes.first.onEvent?(.playbackError(videoId: id, reason: "<video> error 3"))
    }

    // MARK: Which page gets Chrome's user agent

    @Test func onlyChromeModeGivesThePlayerPageChromesUserAgent() async throws {
        try await withPlayer(lateralus) { player, fakes in
            #expect(fakes.first.userAgent == InnerTubeClient.chromeUserAgent)
            #expect(player.playerUserAgent == InnerTubeClient.chromeUserAgent)
        }
        for mode in [PlayerService.GaplessMode.off, .nativeQueue, .secondPlayer] {
            try await withPlayer(lateralus, gapless: mode) { player, fakes in
                #expect(fakes.first.userAgent == InnerTubeClient.safariUserAgent, "\(mode) presented Chrome")
                #expect(!fakes.first.calls.contains { $0.hasPrefix("userAgent:") })
            }
        }
    }

    @Test func theRealPlayerPageGetsItAndTheOtherClientsKeepSafari() async throws {
        let keys = ["playbackState", PlayerService.gaplessModeKey]
        let saved = keys.map { UserDefaults.standard.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, saved) {
                if let value { UserDefaults.standard.set(value, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
            }
        }
        UserDefaults.standard.removeObject(forKey: "playbackState")
        UserDefaults.standard.set(PlayerService.GaplessMode.chromeQueue.rawValue, forKey: PlayerService.gaplessModeKey)
        // The default web player, made the way the app makes it; nothing is loaded.
        let player = PlayerService(auth: AuthService())
        #expect(player.bridge.webView?.customUserAgent == InnerTubeClient.chromeUserAgent)
        player.gaplessMode = .nativeQueue
        #expect(player.bridge.webView?.customUserAgent == InnerTubeClient.safariUserAgent)

        // InnerTube calls and the login page use this one, which must stay Safari's.
        #expect(!InnerTubeClient.safariUserAgent.contains("Chrome"))
        #expect(InnerTubeClient.chromeUserAgent.contains("Chrome/"))
        #expect(PlayerBridge(dataStore: .nonPersistent()).webView?.customUserAgent == InnerTubeClient.safariUserAgent)
    }

    @Test func theStandbyNeverGetsChromesUserAgent() async throws {
        try await withPlayer(lateralus) { player, fakes in
            fakes.startPlaying(player)
            player.gaplessMode = .secondPlayer
            fakes.first.report("grudge", time: 3)
            #expect(fakes.first.userAgent == InnerTubeClient.safariUserAgent)
            #expect(fakes.second?.userAgent == InnerTubeClient.safariUserAgent)
            #expect(fakes.second?.calls.contains { $0.hasPrefix("userAgent:") } == false)
        }
    }

    // MARK: Switching reloads

    @Test func switchingInReloadsTheSongWhereItWas() async throws {
        try await withPlayer(lateralus, gapless: .nativeQueue) { player, fakes in
            fakes.startPlaying(player)
            fakes.first.report("grudge", time: 120)
            player.gaplessMode = .chromeQueue
            let calls = fakes.first.calls
            let ua = try #require(calls.lastIndex(of: "userAgent:chrome"))
            #expect(calls.lastIndex(of: "load:grudge")! > ua, "loaded before the user agent changed")
            #expect(fakes.first.loads == ["grudge", "grudge"])
            #expect(player.currentTime == 120, "the position dipped while reloading")
            fakes.first.report("grudge", time: 0.3)
            #expect(fakes.first.calls.last == "seek", "didn't go back to where it was")
        }
    }

    @Test func switchingOutReloadsAsSafari() async throws {
        try await withPlayer(lateralus) { player, fakes in
            fakes.startPlaying(player)
            player.gaplessMode = .off
            #expect(fakes.first.userAgent == InnerTubeClient.safariUserAgent)
            #expect(fakes.first.calls.suffix(2) == ["userAgent:safari", "load:grudge"])
        }
    }

    @Test func switchingWhilePausedReloadsOnPlay() async throws {
        try await withPlayer(lateralus, gapless: .nativeQueue) { player, fakes in
            fakes.startPlaying(player)
            fakes.first.report("grudge", time: 60)
            player.pause()
            player.gaplessMode = .chromeQueue
            #expect(fakes.first.loads == ["grudge"], "a paused song started playing on its own")
            player.resume()
            #expect(fakes.first.loads == ["grudge", "grudge"])
        }
    }

    @Test func switchingWithoutAUserAgentChangeDoesNotReload() async throws {
        try await withPlayer(lateralus, gapless: .nativeQueue) { player, fakes in
            fakes.startPlaying(player)
            player.gaplessMode = .off
            #expect(fakes.first.loads == ["grudge"])
            #expect(!fakes.first.calls.contains { $0.hasPrefix("userAgent:") })
        }
    }

    // MARK: The queue path is native queue's

    @Test func theNextSongIsQueuedNativelyAndAdopted() async throws {
        try await withPlayer(lateralus) { player, fakes in
            fakes.startPlaying(player)
            #expect(fakes.first.queuedNext == ["eon>grudge"])
            confirm(fakes, "eon")
            fakes.first.onEvent?(.ended(videoId: "grudge"))
            fakes.first.report("eon", time: 0.2)
            #expect(player.current?.id == "eon")
            #expect(fakes.first.loads == ["grudge"])
            #expect(fakes.all.count == 1, "Chrome mode made a standby")
        }
    }

    @Test func aSameElementContinuationIsAdoptedWithItsOwnClock() async throws {
        try await withPlayer(lateralus) { player, fakes in
            fakes.startPlaying(player)
            confirm(fakes, "eon")
            fakes.first.report("grudge", time: 302, duration: 600)
            #expect(player.nativeAdvance?.continuation?.boundary == 300)
            fakes.first.report("eon", time: 303, duration: 600)
            #expect(player.current?.id == "eon")
            #expect(fakes.first.loads == ["grudge"], "loaded a song the stream was already playing")
            #expect(player.currentTime == 3)
            #expect(player.duration == 300)
            fakes.first.report("eon", time: 450, duration: 600)
            #expect(player.currentTime == 150)
            // The next song appended in turn is a continuation from eon's own end.
            confirm(fakes, "patient")
            fakes.first.report("eon", time: 602, duration: 900)
            fakes.first.report("patient", time: 603, duration: 900)
            #expect(player.current?.id == "patient")
            #expect(player.currentTime == 3)
            #expect(fakes.first.loads == ["grudge"])
        }
    }

    @Test func theNewIdShowingPastTheOldEndIsAContinuationToo() async throws {
        try await withPlayer(lateralus) { player, fakes in
            fakes.startPlaying(player)
            confirm(fakes, "eon")
            fakes.first.report("eon", time: 302, duration: 600)
            #expect(player.current?.id == "eon")
            #expect(player.currentTime == 2)
            #expect(fakes.first.loads == ["grudge"])
        }
    }

    // MARK: Errors fall back, and two in a row revert to Safari

    @Test func aPlaybackErrorLoadsTheSongAgain() async throws {
        try await withPlayer(lateralus) { player, fakes in
            fakes.startPlaying(player)
            fail(fakes, "grudge")
            #expect(fakes.first.loads == ["grudge", "grudge"])
            #expect(player.chromeFailures == 1)
            #expect(fakes.first.userAgent == InnerTubeClient.chromeUserAgent)
            #expect(!player.isChromeModeSuspended)
        }
    }

    @Test func twoErrorsInARowPutThePageBackOnSafariForTheSession() async throws {
        try await withPlayer(lateralus) { player, fakes in
            fakes.startPlaying(player)
            fail(fakes, "grudge")
            fail(fakes, "grudge")
            #expect(player.isChromeModeSuspended)
            #expect(fakes.first.userAgent == InnerTubeClient.safariUserAgent)
            #expect(fakes.first.calls.suffix(2) == ["userAgent:safari", "load:grudge"], "didn't keep playing")
            #expect(player.gaplessMode == .chromeQueue, "the setting itself changed")
            #expect(player.playerUserAgent == InnerTubeClient.safariUserAgent)
            // Still following YouTube's own queue, and later errors are only traced.
            fakes.first.report("grudge")
            #expect(fakes.first.queuedNext.last == "eon>grudge")
            fail(fakes, "grudge")
            #expect(fakes.first.loads == ["grudge", "grudge", "grudge"])
            // Choosing the mode again this session doesn't bring Chrome back.
            player.gaplessMode = .nativeQueue
            player.gaplessMode = .chromeQueue
            #expect(fakes.first.userAgent == InnerTubeClient.safariUserAgent)
        }
    }

    @Test func aSongThatPlaysEndsTheRunOfErrors() async throws {
        try await withPlayer(lateralus) { player, fakes in
            fakes.startPlaying(player)
            fail(fakes, "grudge")
            fakes.first.report("grudge", time: 5)
            #expect(player.chromeFailures == 0)
            fail(fakes, "grudge")
            #expect(!player.isChromeModeSuspended)
        }
    }

    @Test func anErrorDuringAMoveLoadsTheExpectedSong() async throws {
        try await withPlayer(lateralus) { player, fakes in
            fakes.startPlaying(player)
            confirm(fakes, "eon")
            fakes.first.onEvent?(.ended(videoId: "grudge"))
            fail(fakes, "eon")
            #expect(player.nativeAdvance == nil)
            #expect(player.current?.id == "eon")
            #expect(fakes.first.loads == ["grudge", "eon"])
        }
    }

    @Test func anErrorForAnotherSongIsIgnored() async throws {
        try await withPlayer(lateralus) { player, fakes in
            fakes.startPlaying(player)
            fail(fakes, "schism")
            #expect(player.chromeFailures == 0)
            #expect(fakes.first.loads == ["grudge"])
        }
    }

    @Test func errorsOutsideChromeModeOnlyTrace() async throws {
        try await withPlayer(lateralus, gapless: .nativeQueue) { player, fakes in
            fakes.startPlaying(player)
            fail(fakes, "grudge")
            fail(fakes, "grudge")
            #expect(fakes.first.loads == ["grudge"])
            #expect(!player.isChromeModeSuspended)
        }
    }

    @Test func aSongThatNeverStartsCountsAsAnError() async throws {
        try await withPlayer(lateralus) { player, fakes in
            player.chromeStartTimeout = .milliseconds(20)
            player.resume()
            try await Task.sleep(for: .milliseconds(400))
            #expect(player.isChromeModeSuspended)
            #expect(fakes.first.loads == ["grudge", "grudge", "grudge"])
            #expect(fakes.first.userAgent == InnerTubeClient.safariUserAgent)
        }
    }

    @Test func aSongThatStartsIsNotTimedOut() async throws {
        try await withPlayer(lateralus) { player, fakes in
            player.chromeStartTimeout = .milliseconds(20)
            player.resume()
            fakes.first.onEvent?(.playing(videoId: "grudge"))
            try await Task.sleep(for: .milliseconds(150))
            #expect(fakes.first.loads == ["grudge"])
            #expect(player.chromeFailures == 0)
        }
    }

    @Test func aMoveThatNeverArrivesCountsAsAnError() async throws {
        try await withPlayer(lateralus) { player, fakes in
            player.nativeAdvanceTimeout = .milliseconds(20)
            fakes.startPlaying(player)
            confirm(fakes, "eon")
            fakes.first.onEvent?(.ended(videoId: "grudge"))
            try await Task.sleep(for: .milliseconds(150))
            #expect(fakes.first.loads == ["grudge", "eon"])
            #expect(player.chromeFailures == 1)
        }
    }
}
