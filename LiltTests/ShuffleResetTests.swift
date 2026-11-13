import Foundation
import Testing
@testable import Lilt

/// Shuffle belongs to the list it was turned on for. Picking a song, pressing Play or starting
/// a mix plays a new list in its own order, so shuffle goes off; only Shuffle Play turns it on.
@MainActor
struct ShuffleResetTests {
    private let schism = Track(id: "tuw1ziytBDk", title: "Schism", artist: "Tool")
    private let forty = Track(id: "ZLDUbN0Gp2M", title: "Forty Six & 2", artist: "Tool")
    private let lateralus = Track(id: "Y7JG63IuaWs", title: "Lateralus", artist: "Tool")
    private let parabola = Track(id: "VtNxCk5Ag7w", title: "Parabola", artist: "Tool")
    private let sober = Track(id: "nspxAG12Cpc", title: "Sober", artist: "Tool")

    private func shuffledPlayer(_ body: (PlayerService) async throws -> Void) async throws {
        try await withFakePlayer([forty, lateralus, parabola, sober], gapless: false) { player, _ in
            player.toggleShuffle()
            #expect(player.isShuffled)
            try await body(player)
        }
    }

    @Test func pickingASongTurnsShuffleOff() async throws {
        try await shuffledPlayer { player in
            let album = [schism, forty, lateralus, parabola, sober]
            player.play(album, startingAt: 1)
            #expect(!player.isShuffled)
            #expect(player.current?.id == forty.id)
            #expect(player.queue.map(\.id) == album.map(\.id), "the album plays on in its own order")
        }
    }

    @Test func startingAMixTurnsShuffleOff() async throws {
        try await shuffledPlayer { player in
            let mix = [schism, parabola, sober, lateralus]
            player.playMix(mix, source: BrowseItem(id: "RDAMVMtuw1ziytBDk", kind: .playlist, title: "Mix – Schism", subtitle: "Mix", artworkURL: nil))
            #expect(!player.isShuffled)
            #expect(player.queue.map(\.id) == mix.map(\.id))
        }
    }

    @Test func aMixFromTheSongPlayingTurnsShuffleOffToo() async throws {
        try await shuffledPlayer { player in
            let current = try #require(player.current)
            let mix = [current, schism, parabola]
            player.playMix(mix, source: BrowseItem(id: "RDAMVM\(current.id)", kind: .playlist, title: "Mix", subtitle: "Mix", artworkURL: nil))
            #expect(!player.isShuffled)
            #expect(player.queue.map(\.id) == mix.map(\.id))
        }
    }

    @Test func shufflePlayStillShuffles() async throws {
        try await withFakePlayer([forty], gapless: false) { player, _ in
            player.playShuffled([schism, forty, lateralus, parabola, sober])
            #expect(player.isShuffled)
        }
    }
}
