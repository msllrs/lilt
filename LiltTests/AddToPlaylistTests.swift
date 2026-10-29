import Foundation
import Testing
@testable import Lilt

/// Adding to one of your playlists: the menu lists the playlists YouTube's own dialog offers,
/// a song goes in by video id, an album or playlist by its whole list, and the menu ticks the
/// playlist afterwards.
@MainActor
struct AddToPlaylistTests {
    @Test func theDialogsPlaylistsAreYours() {
        func option(_ id: String, _ title: String) -> [String: Any] {
            ["playlistAddToOptionRenderer": ["playlistId": id, "title": ["runs": [["text": title]]]]]
        }
        let response: [String: Any] = ["contents": [["addToPlaylistRenderer": ["playlists": [
            option("SE", "Episodes for Later"), option("PLa", "☠️ 1001"), option("PLb", "run"),
        ]]]]]
        #expect(SearchParser.ownPlaylists(from: response) == [OwnPlaylist(id: "PLa", title: "☠️ 1001"), OwnPlaylist(id: "PLb", title: "run")],
                "podcast episodes aren't a playlist for songs")
    }

    private let playlist = OwnPlaylist(id: "PLmine", title: "run")

    @Test func aSongGoesInByVideoId() async throws {
        var calls: [(String, [String: Any])] = []
        let music = YTMusicClient(auth: AuthService(), write: { endpoint, body in
            calls.append((endpoint, body))
            return JSONObject(value: [:])
        })
        let song = Track(id: "v1", title: "Schism", artist: "Tool")
        try await music.add(song, to: playlist)
        let (endpoint, body) = try #require(calls.first)
        #expect(endpoint == "browse/edit_playlist")
        #expect(JSON.string(body["playlistId"]) == "PLmine")
        let action = try #require(JSON.array(body["actions"])?.first.flatMap(JSON.dict))
        #expect(JSON.string(action["action"]) == "ACTION_ADD_VIDEO")
        #expect(JSON.string(action["addedVideoId"]) == "v1")
        #expect(JSON.string(action["dedupeOption"]) == "DEDUPE_OPTION_CHECK", "YouTube won't add it twice")
        #expect(music.addedTo["v1"] == ["PLmine"])
    }

    @Test func anAlbumGoesInAsItsWholeList() async throws {
        var calls: [(String, [String: Any])] = []
        let album = BrowseItem(id: "MPREb-lateralus", kind: .album, title: "Lateralus", subtitle: "Tool", artworkURL: nil)
        let music = YTMusicClient(
            auth: AuthService(),
            fetchPage: { _ in
                JSONObject(value: ["header": ["musicResponsiveHeaderRenderer": [
                    "title": ["runs": [["text": "Lateralus"]]],
                    "buttons": [["watchPlaylistEndpoint": ["playlistId": "OLAK5uy_lateralus"]]],
                ]]])
            },
            write: { endpoint, body in
                calls.append((endpoint, body))
                return JSONObject(value: [:])
            }
        )
        try await music.add(album, to: playlist)
        let body = try #require(calls.first?.1)
        let action = try #require(JSON.array(body["actions"])?.first.flatMap(JSON.dict))
        #expect(JSON.string(action["action"]) == "ACTION_ADD_PLAYLIST")
        #expect(JSON.string(action["addedFullListId"]) == "OLAK5uy_lateralus")
        #expect(music.addedTo[album.id] == ["PLmine"])
    }

    @Test func aFailedAddTicksNothing() async {
        let music = YTMusicClient(auth: AuthService(), write: { _, _ in throw URLError(.notConnectedToInternet) })
        await #expect(throws: URLError.self) { try await music.add(Track(id: "v1", title: "", artist: ""), to: playlist) }
        #expect(music.addedTo["v1"] == nil)
    }

    @Test func playlistsAreFetchedOnceAheadOfTheMenu() async {
        var asks = 0
        let music = YTMusicClient(auth: AuthService(), write: { endpoint, _ in
            if endpoint == "playlist/get_add_to_playlist" { asks += 1 }
            return JSONObject(value: ["contents": [["playlistAddToOptionRenderer": ["playlistId": "PLmine", "title": ["runs": [["text": "run"]]]]]]])
        })
        music.warmOwnPlaylists(videoId: "v1")
        music.warmOwnPlaylists(videoId: "v2")
        for _ in 0..<50 where music.ownPlaylists.isEmpty { try? await Task.sleep(for: .milliseconds(10)) }
        music.warmOwnPlaylists(videoId: "v3")
        #expect(music.ownPlaylists == [playlist])
        #expect(asks == 1)
    }
}
