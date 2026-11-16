import Foundation
import Testing
@testable import Lilt

/// Rows that arrive without an album or artist id (home feed, radio continuation, some playlist
/// rows) look their links up once, ahead of the menu, so Go to Album and Go to Artist appear
/// whenever YouTube knows them.
@MainActor
struct LinkWarmingTests {
    /// A home feed song: an artist name but neither id.
    private let song = Track(id: "tuw1ziytBDk", title: "Schism", artist: "Tool")

    /// The up-next panel's entry for the song, the way `next` answers.
    private func nextResponse(album: Bool) -> JSONObject {
        var runs: [[String: Any]] = [[
            "text": "Tool",
            "navigationEndpoint": ["browseEndpoint": ["browseId": "UCtool", "browseEndpointContextSupportedConfigs": [
                "browseEndpointContextMusicConfig": ["pageType": "MUSIC_PAGE_TYPE_ARTIST"],
            ]]],
        ]]
        if album {
            runs += [["text": " • "], [
                "text": "Lateralus",
                "navigationEndpoint": ["browseEndpoint": ["browseId": "MPREb-lateralus", "browseEndpointContextSupportedConfigs": [
                    "browseEndpointContextMusicConfig": ["pageType": "MUSIC_PAGE_TYPE_ALBUM"],
                ]]],
            ]]
        }
        return JSONObject(value: ["contents": [["playlistPanelVideoRenderer": [
            "videoId": song.id, "longBylineText": ["runs": runs],
        ]]]])
    }

    @Test func aSongGainsGoToAlbumOnceItsLinksAreResolved() async {
        let music = YTMusicClient(auth: AuthService(), fetchNext: { _ in nextResponse(album: true) })
        #expect(!RowMenu.track(music.withLinks(song), in: nil).joined().contains(.goToAlbum), "nothing is known yet")
        await music.warmLinks(for: song)?.value
        let filled = music.withLinks(song)
        #expect(RowMenu.track(filled, in: nil).joined().contains(.goToAlbum))
        #expect(RowMenu.track(filled, in: nil).joined().contains(.goToArtist))
        #expect(filled.albumItem?.id == "MPREb-lateralus")
        #expect(filled.album == "Lateralus")
        #expect(filled.artistItem?.id == "UCtool")
    }

    @Test func aSongWhoseLookupFindsNoAlbumStillHasNoGoToAlbum() async {
        let music = YTMusicClient(auth: AuthService(), fetchNext: { _ in nextResponse(album: false) })
        await music.warmLinks(for: song)?.value
        #expect(!RowMenu.track(music.withLinks(song), in: nil).joined().contains(.goToAlbum))
    }

    @Test func repeatedWarmingForOneSongMakesOneRequest() async {
        var requests = 0
        let music = YTMusicClient(auth: AuthService(), fetchNext: { _ in
            requests += 1
            return JSONObject(value: [:])
        })
        let first = music.warmLinks(for: song)
        music.warmLinks(for: song)
        await first?.value
        music.warmLinks(for: song)
        #expect(requests == 1, "in flight, then found nothing: neither asks again")
    }

    @Test func aSongThatAlreadyHasItsLinksIsNotLookedUp() {
        var requests = 0
        let music = YTMusicClient(auth: AuthService(), fetchNext: { _ in
            requests += 1
            return JSONObject(value: [:])
        })
        var linked = song
        linked.artistId = "UCtool"
        linked.albumId = "MPREb-lateralus"
        #expect(music.warmLinks(for: linked) == nil)
        #expect(requests == 0)
    }

    /// The player looking up the playing song's links and a hover warming the same song's row
    /// at once share one request; the diagnostics log showed four songs in fifty asked twice,
    /// 11ms apart. A song already looked up isn't asked about again by either.
    @Test func thePlayerAndAHoverShareOneLookup() async throws {
        var asked = 0
        let music = YTMusicClient(auth: AuthService(), fetchNext: { _ in
            asked += 1
            try await Task.sleep(for: .milliseconds(50))
            return nextResponse(album: true)
        })
        async let fromPlayer = music.links(forVideoId: song.id)
        let warming = music.warmLinks(for: song)
        let links = try await fromPlayer
        await warming?.value
        #expect(asked == 1, "one request for both (\(asked))")
        #expect(links?.albumId == "MPREb-lateralus")
        _ = try await music.links(forVideoId: song.id)
        #expect(asked == 1, "and none for a song already looked up")
    }
}
