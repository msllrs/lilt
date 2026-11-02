import Foundation
import Testing
@testable import Lilt

/// Native queue mode keeps YouTube Music's own Up Next holding the song Lilt plays next, lets the
/// page's player move on to it by itself, and follows along instead of loading it. These drive
/// `PlayerService` with a fake web player: what's checked is what gets queued for each state of
/// the queue, when it's asked again, that an expected move is adopted without a load, and that
/// anything else (no confirmation, a wrong song, no move in time, a stale `ended`) ends in
/// today's ordinary load.
@MainActor
struct NativeQueueTests {
    private func song(_ id: String) -> Track { Track(id: id, title: id, artist: "Tool") }
    private var lateralus: [Track] { ["grudge", "eon", "patient", "mantra"].map(song) }

    private func withPlayer(
        _ queue: [Track], _ body: (PlayerService, FakePlayers) async throws -> Void
    ) async throws {
        try await withFakePlayer(queue, gapless: .nativeQueue, body)
    }

    /// The page confirming `id` is next in its Up Next.
    private func confirm(_ fakes: FakePlayers, _ id: String) {
        fakes.first.onEvent?(.queuedNext(videoId: id, ok: true, reason: "queue-readback-confirmed"))
    }

    /// Plays the first song, has YouTube's queue confirm the second, and ends the first.
    private func endFirstWithSecondQueued(_ player: PlayerService, _ fakes: FakePlayers) {
        fakes.startPlaying(player)
        confirm(fakes, player.followingTrack!.id)
        fakes.first.onEvent?(.ended(videoId: player.current!.id))
    }

    // MARK: What gets queued

    @Test func theFollowingSongIsQueuedOnceTheCurrentOneIsUnderWay() async throws {
        try await withPlayer(lateralus) { player, fakes in
            player.resume()
            #expect(fakes.first.queuedNext.isEmpty, "queued while the song was still loading")
            fakes.first.report("grudge")
            #expect(fakes.first.queuedNext == ["eon>grudge"])
            #expect(player.nativeTarget == "eon")
            #expect(!player.isNativeQueued)
            fakes.first.report("grudge", time: 2)
            #expect(fakes.first.queuedNext == ["eon>grudge"], "asked again with nothing changed")
            confirm(fakes, "eon")
            #expect(player.isNativeQueued)
            #expect(fakes.all.count == 1, "native queue made a second web player")
        }
    }

    @Test func theEndOfTheQueueQueuesOnlyWithRepeatAll() async throws {
        try await withPlayer([song("parabol"), song("parabola")]) { player, fakes in
            fakes.startPlaying(player)
            player.next()
            fakes.first.report("parabola")
            #expect(player.nativeTarget == nil, "queued past the end of the queue")
            player.setRepeat(.all)
            #expect(fakes.first.queuedNext.last == "parabol>parabola")
            player.setRepeat(.off)
            #expect(player.nativeTarget == nil)
            #expect(fakes.first.calls.last == "cancelQueueNext")
        }
    }

    @Test func repeatOneQueuesNothingAndReplaysThroughALoad() async throws {
        try await withPlayer(lateralus) { player, fakes in
            fakes.startPlaying(player)
            confirm(fakes, "eon")
            player.setRepeat(.one)
            #expect(player.nativeTarget == nil)
            fakes.first.onEvent?(.ended(videoId: "grudge"))
            #expect(player.nativeAdvance == nil)
            #expect(fakes.first.loads == ["grudge", "grudge"])
        }
    }

    @Test func theSameSongNextIsNotQueued() async throws {
        try await withPlayer([song("schism"), song("schism"), song("parabola")]) { player, fakes in
            fakes.startPlaying(player)
            #expect(fakes.first.queuedNext.isEmpty, "a second copy of the playing song can't be told apart in YouTube's queue")
            fakes.first.onEvent?(.ended(videoId: "schism"))
            #expect(fakes.first.loads == ["schism", "schism"])
            #expect(player.currentIndex == 1)
        }
    }

    // MARK: Asked again when what plays next changes

    @Test func editsShuffleAndRepeatAskAgain() async throws {
        try await withPlayer(lateralus) { player, fakes in
            fakes.startPlaying(player)
            confirm(fakes, "eon")
            player.playNext([song("schism")])
            #expect(fakes.first.queuedNext.last == "schism>grudge")
            #expect(!player.isNativeQueued)
            player.enqueue(song("parabola"))
            #expect(fakes.first.queuedNext.count == 2, "asked again for an add that doesn't change what's next")
            player.removeUpcoming(at: 0)
            #expect(fakes.first.queuedNext.last == "parabola>grudge")
            player.toggleShuffle()
            #expect(player.nativeTarget == player.followingTrack?.id)
            player.setRepeat(.one)
            #expect(player.nativeTarget == nil)
        }
    }

    @Test func aSkipAsksAgainForTheNewSong() async throws {
        try await withPlayer(lateralus) { player, fakes in
            fakes.startPlaying(player)
            confirm(fakes, "eon")
            player.next()
            #expect(fakes.first.loads == ["grudge", "eon"], "a manual Next didn't load")
            #expect(player.nativeTarget == nil)
            fakes.first.report("eon")
            #expect(fakes.first.queuedNext.last == "patient>eon")
        }
    }

    @Test func aStaleConfirmationIsIgnored() async throws {
        try await withPlayer(lateralus) { player, fakes in
            fakes.startPlaying(player)
            player.playNext([song("schism")])
            confirm(fakes, "eon")   // the earlier ask, answered late
            #expect(player.nativeTarget == "schism")
            #expect(!player.isNativeQueued)
            fakes.first.onEvent?(.ended(videoId: "grudge"))
            #expect(fakes.first.loads.last == "schism")
        }
    }

    @Test func aFailedAskIsRetriedAFewTimesThenLeftAlone() async throws {
        try await withPlayer(lateralus) { player, fakes in
            fakes.startPlaying(player)
            for _ in 0..<5 {
                fakes.first.onEvent?(.queuedNext(videoId: "eon", ok: false, reason: "play-next-item-not-found"))
                player.setRepeat(.all)   // a save; what plays next is unchanged
            }
            #expect(fakes.first.queuedNext.count == PlayerService.nativeAttempts)
            fakes.first.onEvent?(.ended(videoId: "grudge"))
            #expect(fakes.first.loads.last == "eon")
        }
    }

    // MARK: Following the page's own move

    @Test func anExpectedMoveIsAdoptedWithoutALoad() async throws {
        try await withPlayer(lateralus) { player, fakes in
            endFirstWithSecondQueued(player, fakes)
            #expect(player.nativeAdvance?.targetId == "eon")
            #expect(player.current?.id == "grudge", "moved on before the page did")
            #expect(player.isPlaying, "the button flipped to play between songs")
            fakes.first.report("grudge", playing: false, time: 300)
            #expect(player.current?.id == "grudge")
            fakes.first.report("eon", time: 0.2)
            #expect(player.current?.id == "eon")
            #expect(player.currentIndex == 1)
            #expect(player.nativeAdvance == nil)
            #expect(fakes.first.loads == ["grudge"], "loaded a song the page was already playing")
            #expect(fakes.first.queuedNext.last == "patient>eon")
        }
    }

    @Test func theNewSongSoundingIsAnAdvanceToo() async throws {
        try await withPlayer(lateralus) { player, fakes in
            endFirstWithSecondQueued(player, fakes)
            fakes.first.onEvent?(.playing(videoId: "eon"))
            #expect(player.current?.id == "eon")
            #expect(fakes.first.loads == ["grudge"])
        }
    }

    @Test func aMoveWithNoEndedIsAdoptedToo() async throws {
        try await withPlayer(lateralus) { player, fakes in
            fakes.startPlaying(player)
            confirm(fakes, "eon")
            fakes.first.report("eon", time: 0.1)
            #expect(player.current?.id == "eon")
            #expect(fakes.first.loads == ["grudge"])
            // The `ended` that comes after, for the old song, changes nothing.
            fakes.first.onEvent?(.ended(videoId: "grudge"))
            #expect(player.current?.id == "eon")
            #expect(fakes.first.loads == ["grudge"])
        }
    }

    @Test func oneContinuousStreamPastTheOldEndStartsTheMove() async throws {
        try await withPlayer(lateralus) { player, fakes in
            fakes.startPlaying(player)
            confirm(fakes, "eon")
            fakes.first.report("grudge", time: 302, duration: 600)
            #expect(player.nativeAdvance?.targetId == "eon")
            #expect(player.currentTime == 1, "showed the next song's time as the old one's")
            fakes.first.report("eon", time: 2, duration: 600)
            #expect(player.current?.id == "eon")
            #expect(fakes.first.loads == ["grudge"])
        }
    }

    @Test func handQueuedSongsAreConsumedByAnAdoptedMove() async throws {
        try await withPlayer(lateralus) { player, fakes in
            fakes.startPlaying(player)
            player.playNext([song("schism"), song("parabola")])
            confirm(fakes, "schism")
            fakes.first.onEvent?(.ended(videoId: "grudge"))
            fakes.first.report("schism")
            #expect(player.current?.id == "schism")
            #expect(player.upcoming.map(\.id) == ["parabola"])
            #expect(fakes.first.queuedNext.last == "parabola>schism")
        }
    }

    @Test func aRepeatedSongIsFollowedToItsOwnPlaceInTheQueue() async throws {
        try await withPlayer(["grudge", "eon", "grudge", "eon"].map(song)) { player, fakes in
            endFirstWithSecondQueued(player, fakes)
            fakes.first.report("eon")
            #expect(player.currentIndex == 1)
            confirm(fakes, "grudge")
            fakes.first.onEvent?(.ended(videoId: "eon"))
            fakes.first.report("grudge")
            #expect(player.currentIndex == 2, "went back to the first copy")
            #expect(fakes.first.loads == ["grudge"])
        }
    }

    @Test func repeatAllWrapsNatively() async throws {
        try await withPlayer([song("parabol"), song("parabola")]) { player, fakes in
            fakes.startPlaying(player)
            player.setRepeat(.all)
            player.next()
            fakes.first.report("parabola")
            confirm(fakes, "parabol")
            fakes.first.onEvent?(.ended(videoId: "parabola"))
            fakes.first.report("parabol")
            #expect(player.currentIndex == 0)
            #expect(fakes.first.loads == ["parabol", "parabola"])
        }
    }

    // MARK: Fallback to the ordinary load

    @Test func anUnconfirmedQueueLoadsAsToday() async throws {
        try await withPlayer(lateralus) { player, fakes in
            fakes.startPlaying(player)
            fakes.first.onEvent?(.ended(videoId: "grudge"))
            #expect(player.nativeAdvance == nil)
            #expect(fakes.first.loads == ["grudge", "eon"])
        }
    }

    @Test func aMoveToSomethingElseLoadsTheExpectedSong() async throws {
        try await withPlayer(lateralus) { player, fakes in
            endFirstWithSecondQueued(player, fakes)
            fakes.first.report("vicarious")
            #expect(fakes.first.loads == ["grudge", "eon"])
            #expect(player.current?.id == "eon")
            #expect(!player.queue.contains { $0.id == "vicarious" }, "YouTube's pick was adopted")
        }
    }

    @Test func noMoveInTimeLoadsTheExpectedSong() async throws {
        try await withPlayer(lateralus) { player, fakes in
            player.nativeAdvanceTimeout = .milliseconds(20)
            endFirstWithSecondQueued(player, fakes)
            try await Task.sleep(for: .milliseconds(200))
            #expect(fakes.first.loads == ["grudge", "eon"])
            #expect(player.current?.id == "eon")
        }
    }

    @Test func anAdoptedMoveIsLeftAlone() async throws {
        try await withPlayer(lateralus) { player, fakes in
            player.nativeAdvanceTimeout = .milliseconds(20)
            endFirstWithSecondQueued(player, fakes)
            fakes.first.report("eon")
            try await Task.sleep(for: .milliseconds(200))
            #expect(fakes.first.loads == ["grudge"])
        }
    }

    @Test func anEditDuringTheMoveLoadsTheNewNextSong() async throws {
        try await withPlayer(lateralus) { player, fakes in
            endFirstWithSecondQueued(player, fakes)
            player.playNext([song("schism")])
            #expect(player.nativeAdvance == nil)
            #expect(fakes.first.loads == ["grudge", "schism"])
            #expect(player.current?.id == "schism")
        }
    }

    @Test func aManualNextDuringTheMoveIsAnOrdinaryLoad() async throws {
        try await withPlayer(lateralus) { player, fakes in
            endFirstWithSecondQueued(player, fakes)
            player.next()
            #expect(player.nativeAdvance == nil)
            #expect(fakes.first.loads == ["grudge", "eon"])
            fakes.first.report("eon")
            #expect(player.currentIndex == 1, "the page's arrival moved Lilt on a second time")
        }
    }

    // MARK: Stale events

    @Test func staleEndedEventsAreIgnored() async throws {
        try await withPlayer(lateralus) { player, fakes in
            fakes.startPlaying(player)
            confirm(fakes, "eon")
            fakes.first.onEvent?(.ended(videoId: "eon"))   // not the song playing
            #expect(player.nativeAdvance == nil)
            #expect(fakes.first.loads == ["grudge"])
            fakes.first.onEvent?(.ended(videoId: "grudge"))
            fakes.first.onEvent?(.ended(videoId: "grudge"))   // a second one for the same end
            #expect(player.nativeAdvance?.targetId == "eon")
            #expect(fakes.first.loads == ["grudge"])
            fakes.first.report("eon")
            fakes.first.onEvent?(.ended(videoId: "grudge"))   // late, after the move
            #expect(player.current?.id == "eon")
            #expect(fakes.first.loads == ["grudge"])
        }
    }

    // MARK: Switching modes

    @Test func switchingToTheSecondPlayerStopsQueueingAndMakesAStandby() async throws {
        try await withPlayer(lateralus) { player, fakes in
            fakes.startPlaying(player)
            #expect(player.nativeTarget == "eon")
            player.gaplessMode = .secondPlayer
            #expect(player.nativeTarget == nil)
            #expect(fakes.first.calls.contains("cancelQueueNext"))
            #expect(fakes.second?.calls == ["cue:eon"])
            fakes.first.onEvent?(.ended(videoId: "grudge"))
            #expect(player.nativeAdvance == nil)
        }
    }

    @Test func switchingOffDuringAMoveLoadsTheSong() async throws {
        try await withPlayer(lateralus) { player, fakes in
            endFirstWithSecondQueued(player, fakes)
            player.gaplessMode = .off
            #expect(player.nativeAdvance == nil)
            #expect(fakes.first.loads == ["grudge", "eon"])
            #expect(fakes.all.count == 1)
        }
    }

    @Test func switchingFromTheSecondPlayerTearsTheStandbyDownAndQueues() async throws {
        try await withFakePlayer(lateralus, gapless: .secondPlayer) { player, fakes in
            fakes.startPlaying(player)
            let standby = try #require(fakes.second)
            player.gaplessMode = .nativeQueue
            #expect(player.standby == nil)
            #expect(standby.calls.last == "unload")
            #expect(fakes.first.queuedNext == ["eon>grudge"])
        }
    }
}
