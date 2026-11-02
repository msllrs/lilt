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
    /// A web player that only records what it was asked to do.
    @MainActor
    final class FakeBridge: PlayerBridging {
        var onEvent: ((PlayerEvent) -> Void)?
        var webView: WKWebView? { nil }
        private(set) var calls: [String] = []

        func warmUp() { calls.append("warmUp") }
        func load(videoId: String) { calls.append("load:\(videoId)") }
        func cue(videoId: String) { calls.append("cue:\(videoId)") }
        func hold() { calls.append("hold") }
        func start() { calls.append("start") }
        func play() { calls.append("play") }
        func pause() { calls.append("pause") }
        func seek(to seconds: Double) { calls.append("seek") }
        func setVolume(_ volume: Double) {}
        func toggleLike() {}
        func unload() { calls.append("unload") }

        /// The page reporting `id` playing at `time`.
        func report(_ id: String, playing: Bool = true, time: Double = 1) {
            onEvent?(.state(PlaybackSnapshot(
                videoId: id, isPlaying: playing, currentTime: time, duration: 300,
                title: id, artist: "Tool", artworkURL: nil,
                artistId: "UC1", albumId: "MPRE1", albumTitle: "Lateralus", likeStatus: nil
            )))
        }
    }

    /// Every fake the player made, in order: the first is the one it starts with.
    final class Fakes {
        var all: [FakeBridge] = []
        var first: FakeBridge { all[0] }
        var second: FakeBridge? { all.count > 1 ? all[1] : nil }
    }

    private func song(_ id: String) -> Track { Track(id: id, title: id, artist: "Tool") }
    private var lateralus: [Track] { ["grudge", "eon", "patient", "mantra"].map(song) }

    /// A player resumed on `queue[0]` with fake web players and gapless set as given. The real
    /// app's saved playback and setting are put back afterwards.
    private func withPlayer(
        _ queue: [Track], gapless: Bool = true,
        _ body: (PlayerService, Fakes) async throws -> Void
    ) async throws {
        let keys = ["playbackState", PlayerService.gaplessKey]
        let saved = keys.map { UserDefaults.standard.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, saved) {
                if let value { UserDefaults.standard.set(value, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
            }
        }
        let state: [String: Any] = ["queue": try JSONSerialization.jsonObject(with: JSONEncoder().encode(queue)), "index": 0, "time": 0]
        UserDefaults.standard.set(try JSONSerialization.data(withJSONObject: state), forKey: "playbackState")
        UserDefaults.standard.set(gapless, forKey: PlayerService.gaplessKey)
        let fakes = Fakes()
        let player = PlayerService(auth: AuthService(), makeBridge: {
            let fake = FakeBridge()
            fakes.all.append(fake)
            return fake
        })
        try await body(player, fakes)
    }

    /// Presses play on the restored song and has the page report it under way.
    private func startPlaying(_ player: PlayerService, _ fakes: Fakes) {
        player.resume()
        fakes.first.report(player.current!.id)
    }

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
}
