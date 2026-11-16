import Foundation
import Testing
@testable import Lilt

/// Previous in the first few seconds of a song goes back to the song before it, as in any
/// music app; past them it starts the song again. A song that has only just come on (by Next,
/// by the last one ending, or by a gapless handover) is in its first seconds however far the
/// one before it had got, so Previous then goes back, rather than restarting the new song
/// because the old song's elapsed time was still showing.
@MainActor
struct PreviousEarlyTests {
    private func song(_ id: String) -> Track { Track(id: id, title: id, artist: "Tool") }
    private var lateralus: [Track] { ["grudge", "eon", "patient"].map(song) }

    @Test func rightAfterNextItGoesBack() async throws {
        try await withFakePlayer(lateralus, gapless: false) { player, fakes in
            fakes.startPlaying(player)
            fakes.first.report("grudge", time: 250)
            player.next()
            #expect(player.current?.id == "eon")
            player.previous()
            #expect(player.current?.id == "grudge", "eon had only just come on (\(player.currentTime)s shown)")
        }
    }

    @Test func rightAfterAGaplessHandoverItGoesBack() async throws {
        try await withFakePlayer(lateralus, gapless: true) { player, fakes in
            fakes.startPlaying(player)
            let standby = try #require(fakes.second)
            standby.onEvent?(.cued(videoId: "eon"))
            fakes.first.report("grudge", time: 298)
            fakes.first.onEvent?(.ended(videoId: "grudge"))
            #expect(player.current?.id == "eon")
            // The held page's last word about the song that ended, as it comes in for real.
            fakes.first.report("grudge", playing: false, time: 300)
            player.previous()
            #expect(player.current?.id == "grudge", "eon had only just come on (\(player.currentTime)s shown)")
        }
    }

    @Test func rightAfterAHandoverByNextItGoesBack() async throws {
        try await withFakePlayer(lateralus, gapless: true) { player, fakes in
            fakes.startPlaying(player)
            let standby = try #require(fakes.second)
            standby.onEvent?(.cued(videoId: "eon"))
            fakes.first.report("grudge", time: 120)
            player.next()
            #expect(player.current?.id == "eon")
            player.previous()
            #expect(player.current?.id == "grudge")
        }
    }

    @Test func pastTheFirstSecondsItStartsTheSongAgain() async throws {
        try await withFakePlayer(lateralus, gapless: false) { player, fakes in
            var clock = Date.now
            player.now = { clock }
            fakes.startPlaying(player)
            player.next()
            clock += 12
            fakes.first.report("eon", time: 12)
            player.previous()
            #expect(player.current?.id == "eon")
            #expect(fakes.first.calls.last == "seek")
        }
    }

    /// The page swaps songs in one <video> element and can report the new song's id with the
    /// old one's time before the element resets: Previous straight after still goes back.
    @Test func aStaleTimeFromThePageStillGoesBack() async throws {
        try await withFakePlayer(lateralus, gapless: false) { player, fakes in
            fakes.startPlaying(player)
            fakes.first.report("grudge", time: 250)
            player.next()
            fakes.first.report("eon", time: 250)
            player.previous()
            #expect(player.current?.id == "grudge", "eon came on a moment ago, whatever time the page last said")
        }
    }
}
