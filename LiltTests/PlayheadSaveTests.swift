import Foundation
import Testing
@testable import Lilt

/// Lilt keeps where you are in a song across a relaunch by saving the playhead every five seconds
/// of playing. The queue is saved with it only when the queue changes: encoding a long album or
/// mix and its unshuffled order into the app's preferences every five seconds, for as long as
/// music plays, is work for nothing.
@MainActor
struct PlayheadSaveTests {
    private func song(_ id: String) -> Track { Track(id: id, title: id, artist: "Tool") }
    private var lateralus: [Track] { ["grudge", "eon", "patient", "mantra"].map(song) }
    private var savedQueue: Data? { UserDefaults.standard.data(forKey: "playbackState") }

    /// Lilt launched again on what was saved, with nothing loaded.
    private func relaunched() -> PlayerService {
        PlayerService(auth: AuthService(), makeBridge: { FakeBridge() })
    }

    @Test func thePlayheadMovingLeavesTheSavedQueueAlone() async throws {
        try await withFakePlayer(lateralus, gapless: false) { player, fakes in
            fakes.startPlaying(player)
            let queue = try #require(savedQueue)
            fakes.first.report("grudge", time: 12)
            fakes.first.report("grudge", time: 30)
            #expect(savedQueue == queue, "the queue was encoded again for the playhead")
        }
    }

    @Test func aRelaunchResumesWhereThePlayheadWas() async throws {
        try await withFakePlayer(lateralus, gapless: false) { player, fakes in
            fakes.startPlaying(player)
            fakes.first.report("grudge", time: 12)
            fakes.first.report("grudge", time: 30)
            let again = relaunched()
            #expect(again.current?.id == "grudge")
            #expect(again.currentTime == 30)
        }
    }

    /// The playhead saved partway through one song isn't the next one's.
    @Test func theNextSongResumesFromItsStart() async throws {
        try await withFakePlayer(lateralus, gapless: false) { player, fakes in
            fakes.startPlaying(player)
            fakes.first.report("grudge", time: 30)
            player.next()
            let again = relaunched()
            #expect(again.current?.id == "eon")
            #expect(again.currentTime == 0)
        }
    }
}
