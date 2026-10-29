import Foundation
import Testing
@testable import Lilt

/// Liking a song from its row: the row's like state comes from the response, the call goes to
/// YouTube Music, and every row agrees at once (or goes back if the call fails).
@MainActor
struct LikeTests {
    private let song = Track(id: "tuw1ziytBDk", title: "Schism", artist: "Tool")

    /// A playlist row's like button, the way Liked Music sends it.
    @Test func playlistRowsCarryALikeButton() {
        let row: [String: Any] = ["menu": ["menuRenderer": ["topLevelButtons": [["likeButtonRenderer": ["likeStatus": "LIKE"]]]]]]
        #expect(SearchParser.likeState(of: row) == true)
        let indifferent: [String: Any] = ["menu": ["menuRenderer": ["topLevelButtons": [["likeButtonRenderer": ["likeStatus": "INDIFFERENT"]]]]]]
        #expect(SearchParser.likeState(of: indifferent) == false)
    }

    /// Search rows carry only the menu's toggle; its default action is what a click would do.
    @Test func searchRowsCarryALikedSongsToggle() {
        func row(_ status: String) -> [String: Any] {
            ["menu": ["menuRenderer": ["items": [["toggleMenuServiceItemRenderer": [
                "defaultServiceEndpoint": ["likeEndpoint": ["status": status, "target": ["videoId": "x"]]],
            ]]]]]]
        }
        #expect(SearchParser.likeState(of: row("LIKE")) == false, "a click would like it, so it isn't liked")
        #expect(SearchParser.likeState(of: row("INDIFFERENT")) == true, "a click would unlike it, so it's liked")
        #expect(SearchParser.likeState(of: [:]) == nil)
    }

    @Test func likingCallsYouTubeMusicAndRowsAgree() async throws {
        var calls: [(String, [String: Any])] = []
        let music = YTMusicClient(auth: AuthService(), write: { endpoint, body in
            calls.append((endpoint, body))
            return JSONObject(value: [:])
        })
        try await music.setLiked(true, track: song)
        #expect(calls.first?.0 == "like/like")
        #expect(JSON.string(JSON.value(at: ["target", "videoId"], in: calls.first?.1)) == song.id)
        #expect(music.isLiked(song) == true)

        try await music.setLiked(false, track: song)
        #expect(calls.last?.0 == "like/removelike")
        #expect(music.isLiked(song) == false)
    }

    @Test func aFailedLikeIsUndone() async {
        let music = YTMusicClient(auth: AuthService(), write: { _, _ in throw URLError(.notConnectedToInternet) })
        var liked = song
        liked.isLiked = true
        await #expect(throws: URLError.self) { try await music.setLiked(false, track: liked) }
        #expect(music.isLiked(liked) == true, "the row goes back to liked")
    }
}
