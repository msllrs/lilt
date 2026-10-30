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
}
