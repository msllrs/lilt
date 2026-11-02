import Foundation
import Testing
import WebKit
@testable import Lilt

/// Gapless playback keeps the next song cued in a second web player and hands over to it when
/// the current one ends. These drive `PlayerService` with fake web players, so nothing loads:
/// what's checked is which song the standby holds, when it's re-cued, that only the player you
/// hear drives playback, and that an unready standby falls back to the ordinary load.
@MainActor
struct GaplessTests {
    private func song(_ id: String) -> Track { Track(id: id, title: id, artist: "Tool") }
    private var lateralus: [Track] { ["grudge", "eon", "patient", "mantra"].map(song) }

    private func withPlayer(
        _ queue: [Track], gapless: Bool = true, legacyMode: String? = nil,
        _ body: (PlayerService, FakePlayers) async throws -> Void
    ) async throws {
        try await withFakePlayer(queue, gapless: gapless, legacyMode: legacyMode, body)
    }

    private func startPlaying(_ player: PlayerService, _ fakes: FakePlayers) { fakes.startPlaying(player) }

    // MARK: Which song the standby holds

    @Test func theStandbyCuesTheNextSongOnceTheCurrentOneIsUnderWay() async throws {
        try await withPlayer(lateralus) { player, fakes in
            #expect(fakes.all.count == 1, "a standby before anything has played")
            player.resume()
            #expect(fakes.all.count == 1, "a standby competing with the song still loading")
            fakes.first.report("grudge")
            #expect(fakes.second?.calls == ["cue:eon"])
            #expect(player.standbyTrackId == "eon")
        }
    }

    @Test func repeatOneHoldsTheSameSong() async throws {
        try await withPlayer(lateralus) { player, fakes in
            startPlaying(player, fakes)
            player.setRepeat(.one)
            #expect(player.standbyTrackId == "grudge")
            #expect(fakes.second?.calls.last == "cue:grudge")
        }
    }

    @Test func atTheEndOfTheQueueItHoldsTheFirstSongOnlyWithRepeatAll() async throws {
        try await withPlayer([song("parabol")]) { player, fakes in
            startPlaying(player, fakes)
            #expect(fakes.all.count == 1, "a standby with nothing after the last song")
            player.setRepeat(.all)
            #expect(player.standbyTrackId == "parabol")
            player.setRepeat(.off)
            #expect(player.standbyTrackId == nil)
            #expect(fakes.second?.calls.last == "hold")
        }
    }

    @Test func editingTheQueueReCuesWhatPlaysNext() async throws {
        try await withPlayer(lateralus) { player, fakes in
            startPlaying(player, fakes)
            player.playNext([song("schism")])
            #expect(player.standbyTrackId == "schism")
            player.enqueue(song("parabola"))
            #expect(fakes.second?.calls == ["cue:eon", "cue:schism"], "re-cued for an add that doesn't change what's next")
            player.removeUpcoming(at: 0)
            #expect(player.standbyTrackId == "parabola")
            player.toggleShuffle()
            #expect(player.standbyTrackId == player.followingTrack?.id)
        }
    }

    @Test func playingSomethingElseReCuesAfterItStarts() async throws {
        try await withPlayer(lateralus) { player, fakes in
            startPlaying(player, fakes)
            player.play(lateralus, startingAt: 2)
            #expect(player.standbyTrackId == "eon", "re-cued before the new song is under way")
            fakes.first.report("patient")
            #expect(player.standbyTrackId == "mantra")
        }
    }

    // MARK: Only the player you hear drives playback

    @Test func theStandbysEventsAreIgnored() async throws {
        try await withPlayer(lateralus) { player, fakes in
            startPlaying(player, fakes)
            let standby = try #require(fakes.second)
            standby.report("eon", time: 0)
            standby.onEvent?(.ended(videoId: "grudge"))
            standby.onEvent?(.remote(.next))
            #expect(player.current?.id == "grudge")
            #expect(player.currentTime == 1)
            #expect(fakes.first.calls.filter { $0.hasPrefix("load:") } == ["load:grudge"])
            #expect(!standby.calls.contains("start"))
        }
    }

    // MARK: Handover and fallback

    @Test func aReadyStandbyTakesOverWhenTheSongEnds() async throws {
        try await withPlayer(lateralus) { player, fakes in
            startPlaying(player, fakes)
            let standby = try #require(fakes.second)
            standby.onEvent?(.cued(videoId: "eon"))
            #expect(player.isStandbyReady)
            fakes.first.onEvent?(.ended(videoId: "grudge"))
            #expect(player.current?.id == "eon")
            #expect(standby.calls.last == "start")
            #expect(fakes.first.calls.last == "hold")
            #expect(!fakes.first.calls.contains("load:eon"))
            #expect(player.bridge === standby)
            // The old player is now the standby; it cues what follows once the new song is heard.
            fakes.first.report("grudge", playing: false, time: 300)
            #expect(player.current?.id == "eon", "the old player's report took over")
            standby.report("eon")
            #expect(fakes.first.calls.last == "cue:patient")
            #expect(player.standbyTrackId == "patient")
        }
    }

    @Test func nextUsesAReadyStandbyToo() async throws {
        try await withPlayer(lateralus) { player, fakes in
            startPlaying(player, fakes)
            let standby = try #require(fakes.second)
            standby.onEvent?(.cued(videoId: "eon"))
            player.next()
            #expect(standby.calls.last == "start")
            #expect(fakes.first.calls.last == "hold")
            #expect(player.current?.id == "eon")
        }
    }

    @Test func anUnreadyStandbyFallsBackToTheOrdinaryLoad() async throws {
        try await withPlayer(lateralus) { player, fakes in
            startPlaying(player, fakes)
            let standby = try #require(fakes.second)
            fakes.first.onEvent?(.ended(videoId: "grudge"))
            #expect(player.current?.id == "eon")
            #expect(fakes.first.calls.last == "load:eon")
            #expect(!standby.calls.contains("start"))
            #expect(player.bridge === fakes.first)
        }
    }

    @Test func aStandbyCuedOnTheWrongSongIsNotUsed() async throws {
        try await withPlayer(lateralus) { player, fakes in
            startPlaying(player, fakes)
            let standby = try #require(fakes.second)
            standby.onEvent?(.cued(videoId: "eon"))
            player.playNext([song("schism")])
            standby.onEvent?(.cued(videoId: "eon"))   // the earlier cue, arriving late
            #expect(!player.isStandbyReady)
            fakes.first.onEvent?(.ended(videoId: "grudge"))
            #expect(fakes.first.calls.last == "load:schism")
            #expect(!standby.calls.contains("start"))
        }
    }

    @Test func aFailedCueFallsBackAndIsNotRetriedForThatSong() async throws {
        try await withPlayer(lateralus) { player, fakes in
            startPlaying(player, fakes)
            let standby = try #require(fakes.second)
            standby.onEvent?(.cueFailed(videoId: "eon"))
            #expect(player.standbyTrackId == nil)
            player.setRepeat(.all)   // what plays next is unchanged
            #expect(standby.calls == ["cue:eon"], "retried a song that failed to cue")
            fakes.first.onEvent?(.ended(videoId: "grudge"))
            #expect(fakes.first.calls.last == "load:eon")
        }
    }

    @Test func aHandoverThatNeverSoundsLoadsTheSongInstead() async throws {
        try await withPlayer(lateralus) { player, fakes in
            player.handoverTimeout = .milliseconds(20)
            startPlaying(player, fakes)
            let standby = try #require(fakes.second)
            standby.onEvent?(.cued(videoId: "eon"))
            fakes.first.onEvent?(.ended(videoId: "grudge"))
            try await Task.sleep(for: .milliseconds(200))
            #expect(standby.calls.last == "load:eon")
        }
    }

    @Test func aHandoverThatSoundsIsLeftAlone() async throws {
        try await withPlayer(lateralus) { player, fakes in
            player.handoverTimeout = .milliseconds(20)
            startPlaying(player, fakes)
            let standby = try #require(fakes.second)
            standby.onEvent?(.cued(videoId: "eon"))
            fakes.first.onEvent?(.ended(videoId: "grudge"))
            standby.onEvent?(.playing(videoId: "eon"))
            try await Task.sleep(for: .milliseconds(200))
            #expect(standby.calls.last == "start")
        }
    }

    // MARK: The setting

    @Test func offThereIsOnlyOneWebPlayer() async throws {
        try await withPlayer(lateralus, gapless: false) { player, fakes in
            startPlaying(player, fakes)
            fakes.first.onEvent?(.ended(videoId: "grudge"))
            #expect(fakes.all.count == 1)
            #expect(fakes.first.calls.filter { $0.hasPrefix("load:") } == ["load:grudge", "load:eon"])
        }
    }

    @Test func turningItOffTearsTheStandbyDown() async throws {
        try await withPlayer(lateralus) { player, fakes in
            startPlaying(player, fakes)
            let standby = try #require(fakes.second)
            standby.onEvent?(.cued(videoId: "eon"))
            player.isGapless = false
            #expect(player.standby == nil)
            #expect(standby.calls.last == "unload")
            fakes.first.onEvent?(.ended(videoId: "grudge"))
            #expect(fakes.first.calls.last == "load:eon")
            player.isGapless = true
            fakes.first.report("eon")
            #expect(fakes.all.count == 3)
            #expect(fakes.all[2].calls == ["cue:patient"])
        }
    }

    @Test func switchingAwayAfterAHandoverKeepsThePlayerYouHear() async throws {
        try await withPlayer(lateralus) { player, fakes in
            startPlaying(player, fakes)
            let standby = try #require(fakes.second)
            standby.onEvent?(.cued(videoId: "eon"))
            fakes.first.onEvent?(.ended(videoId: "grudge"))
            #expect(player.bridge === standby)
            player.isGapless = false
            #expect(player.bridge === standby, "the song you hear was torn down")
            #expect(player.standby == nil)
            #expect(fakes.first.calls.last == "unload")
        }
    }

    @Test func thePickersModeMovesOntoTheSwitch() async throws {
        let modeKey = PlayerService.legacyGaplessModeKey
        // The picker wrote only its own key, so the switch's is whatever was left from before it.
        try await withPlayer(lateralus, gapless: true, legacyMode: "off") { player, fakes in
            #expect(!player.isGapless, "a mode of off came back on")
            #expect(UserDefaults.standard.object(forKey: PlayerService.gaplessKey) as? Bool == false)
            #expect(UserDefaults.standard.object(forKey: modeKey) == nil)
            startPlaying(player, fakes)
            #expect(fakes.all.count == 1)
        }
        for mode in ["nativeQueue", "chromeQueue", "secondPlayer", "somethingNewer"] {
            try await withPlayer(lateralus, gapless: false, legacyMode: mode) { player, fakes in
                #expect(player.isGapless, "\(mode) didn't become the second player")
                #expect(UserDefaults.standard.object(forKey: PlayerService.gaplessKey) as? Bool == true)
                #expect(UserDefaults.standard.object(forKey: modeKey) == nil)
                startPlaying(player, fakes)
                #expect(fakes.second != nil)
            }
        }
    }

    @Test func theSwitchIsStoredAndOnUntilTurnedOff() async throws {
        try await withPlayer(lateralus, gapless: false) { player, _ in
            #expect(!player.isGapless)
            player.isGapless = true
            #expect(PlayerService.storedGapless())
            UserDefaults.standard.removeObject(forKey: PlayerService.gaplessKey)
            #expect(PlayerService.storedGapless(), "gapless isn't on by default")
        }
    }
}
