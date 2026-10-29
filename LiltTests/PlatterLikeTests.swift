import Foundation
import Testing
@testable import Lilt

/// Liking the playing song with the now-playing bar's like button reaches the rows' menus: the
/// same song's row offers Unlike straight away, without waiting for its page to be fetched again.
/// The player reports each like it makes; the app connects that to the client, the way it
/// connects `linkResolver`.
@MainActor
struct PlatterLikeTests {
    @Test func thePlatterHeartReachesTheRows() throws {
        let key = "playbackState"
        let saved = UserDefaults.standard.data(forKey: key)
        defer { if let saved { UserDefaults.standard.set(saved, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) } }
        let schism = Track(id: "tuw1ziytBDk", title: "Schism", artist: "Tool", isLiked: false)
        let state: [String: Any] = ["queue": try JSONSerialization.jsonObject(with: JSONEncoder().encode([schism])), "index": 0, "time": 0]
        UserDefaults.standard.set(try JSONSerialization.data(withJSONObject: state), forKey: key)

        let auth = AuthService()
        let player = PlayerService(auth: auth)
        let music = YTMusicClient(auth: auth, write: { _, _ in Issue.record("the player likes through the web player, not the API"); return JSONObject(value: [:]) })
        player.onLikeToggled = { track, liked in music.noteLiked(liked, track: track) }

        #expect(music.isLiked(schism) == false)
        player.toggleLike()
        #expect(music.isLiked(schism) == true, "the row's menu now offers Unlike")
        player.toggleLike()
        #expect(music.isLiked(schism) == false)
    }
}
