import Foundation
import Testing
@testable import Lilt

/// A song YouTube Music greys out can't be played here, so a list played from Lilt leaves it
/// out of the queue: Play, Shuffle and a click on the song after it all skip it, rather than
/// stopping on a song that never starts.
@MainActor
struct UnavailableSongTests {
    private static func song(_ id: String, unavailable: Bool = false) -> Track {
        Track(id: id, title: id, artist: "Tool", isUnavailable: unavailable ? true : nil)
    }
    private let list = [song("a"), song("gone", unavailable: true), song("b"), song("c")]

    @Test func playingAListLeavesTheGreyedOutSongOut() async throws {
        try await withFakePlayer([Self.song("x")], gapless: false) { player, _ in
            player.play(list, startingAt: 0)
            #expect(player.queue.map(\.id) == ["a", "b", "c"])
            #expect(player.current?.id == "a")
        }
    }

    @Test func aSongAfterItStillPlaysItself() async throws {
        try await withFakePlayer([Self.song("x")], gapless: false) { player, _ in
            player.play(list, startingAt: 2)
            #expect(player.current?.id == "b", "the index is the list's, so the song clicked plays")
        }
    }

    @Test func shuffleNeverLandsOnIt() async throws {
        try await withFakePlayer([Self.song("x")], gapless: false) { player, _ in
            for _ in 0..<20 {
                player.playShuffled(list)
                #expect(!player.queue.contains { $0.id == "gone" })
            }
        }
    }

    @Test func aGreyedOutSongItselfPlaysNothing() async throws {
        try await withFakePlayer([Self.song("x")], gapless: false) { player, _ in
            player.play(list, startingAt: 1)
            #expect(player.current?.id == "x", "nothing changes")
        }
    }

    /// Play Next on a page with a greyed-out first song, with nothing playing, starts from the
    /// first song that plays.
    @Test func playNextLeavesItOutToo() async throws {
        try await withFakePlayer([Self.song("x")], gapless: false) { player, _ in
            player.playNext([Self.song("gone", unavailable: true), Self.song("a"), Self.song("b")])
            #expect(!player.queue.contains { $0.id == "gone" })
        }
    }
}
