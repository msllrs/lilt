import Foundation
import Testing
@testable import Lilt

/// Removing a song from one of your playlists: only your playlists' rows carry the call, it
/// names the song's entry, and the row goes at once (and comes back if the call fails).
@MainActor
struct PlaylistRemovalTests {
    /// A row of your own playlist, shaped the way YouTube Music sends one.
    private let ownRow: [String: Any] = ["menu": ["menuRenderer": ["items": [["menuServiceItemRenderer": [
        "serviceEndpoint": ["playlistEditEndpoint": [
            "playlistId": "PLmine",
            "actions": [["removedVideoId": "v1", "setVideoId": "set1", "action": "ACTION_REMOVE_VIDEO"]],
        ]],
    ]]]]]]

    @Test func yourPlaylistsRowsCarryTheirEntry() {
        #expect(SearchParser.playlistEntry(of: ownRow) == PlaylistEntry(playlistId: "PLmine", setVideoId: "set1"))
        #expect(SearchParser.playlistEntry(of: ["playlistItemData": ["playlistSetVideoId": "set1", "videoId": "v1"]]) == nil,
                "someone else's playlist rows have an entry id but no remove call")
    }

    private var song: Track {
        var track = Track(id: "v1", title: "Schism", artist: "Tool")
        track.playlistEntry = PlaylistEntry(playlistId: "PLmine", setVideoId: "set1")
        return track
    }

    @Test func removingCallsEditPlaylist() async throws {
        var calls: [(String, [String: Any])] = []
        let music = YTMusicClient(auth: AuthService(), write: { endpoint, body in
            calls.append((endpoint, body))
            return JSONObject(value: [:])
        })
        try await music.removeFromPlaylist(song)
        let (endpoint, body) = try #require(calls.first)
        #expect(endpoint == "browse/edit_playlist")
        #expect(JSON.string(body["playlistId"]) == "PLmine")
        let action = try #require(JSON.array(body["actions"])?.first.flatMap(JSON.dict))
        #expect(JSON.string(action["action"]) == "ACTION_REMOVE_VIDEO")
        #expect(JSON.string(action["setVideoId"]) == "set1")
        #expect(JSON.string(action["removedVideoId"]) == "v1")
        #expect(music.isRemoved(song))
    }

    @Test func aFailedRemovalBringsTheRowBack() async {
        let music = YTMusicClient(auth: AuthService(), write: { _, _ in throw URLError(.notConnectedToInternet) })
        await #expect(throws: URLError.self) { try await music.removeFromPlaylist(song) }
        #expect(!music.isRemoved(song))
    }
}
