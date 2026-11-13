import Foundation
import Testing
@testable import Lilt

/// An album or playlist's row and page show as playing (the spinning record) only while the
/// queue started from it is what's playing. Once its songs run out and YouTube Music carries
/// on with a radio pick of its own, the music has left it.
@MainActor
struct SourceContinuationTests {
    private let partyWithTheBoys = Track(id: "pwtb", title: "Party With The Boys", artist: "Don Toliver")
    private let yaHit = Track(id: "yahit", title: "Ya Hit", artist: "Future")
    private let single = BrowseItem(id: "MPREb_8zSkokEMLCb", kind: .album, title: "Party With The Boys", subtitle: "Single • Don Toliver", artworkURL: nil)

    @Test func youTubesOwnContinuationLeavesTheSource() async throws {
        try await withFakePlayer([yaHit], gapless: false) { player, fakes in
            player.play([partyWithTheBoys], startingAt: 0, source: single)
            fakes.first.report(partyWithTheBoys.id)
            #expect(player.sourceId == single.id, "the single is playing")

            // The single ends with nothing after it; YouTube Music moves on to its own pick.
            fakes.first.onEvent?(.ended(videoId: partyWithTheBoys.id))
            fakes.first.report("radio-pick")

            #expect(player.current?.id == "radio-pick")
            #expect(player.sourceId == nil, "the single's row stops spinning")
            #expect(player.sourceTitle == nil, "Up Next isn't \"from\" the single any more")
        }
    }

    @Test func theSourceStaysWhileItsOwnSongsPlay() async throws {
        try await withFakePlayer([yaHit], gapless: false) { player, fakes in
            player.play([partyWithTheBoys, yaHit], startingAt: 0, source: single)
            fakes.first.report(partyWithTheBoys.id)
            fakes.first.onEvent?(.ended(videoId: partyWithTheBoys.id))
            fakes.first.report(yaHit.id)
            #expect(player.current?.id == yaHit.id)
            #expect(player.sourceId == single.id)
        }
    }
}
