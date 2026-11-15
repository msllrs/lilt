import Foundation
import Testing
@testable import Lilt

/// Add to Playlist lists your playlists as they are now: one made on the phone or the web turns
/// up once the list is a few minutes old, without a relaunch (Lilt runs for days), and another
/// account's never shows after you switch to this one.
@MainActor
struct OwnPlaylistsTests {
    private final class Server {
        var playlists: [(String, String)] = [("PLa", "run")]
        var asked = 0
        func response() -> JSONObject {
            JSONObject(value: ["contents": [["addToPlaylistRenderer": ["playlists": playlists.map { id, title in
                ["playlistAddToOptionRenderer": ["playlistId": id, "title": ["runs": [["text": title]]]]]
            }]]]])
        }
    }

    private func client(_ server: Server) -> YTMusicClient {
        YTMusicClient(auth: AuthService(), write: { endpoint, _ in
            guard endpoint == "playlist/get_add_to_playlist" else { return JSONObject(value: [:]) }
            server.asked += 1
            return server.response()
        }, persists: false)
    }

    private func settle(until done: () -> Bool) async {
        for _ in 0..<50 where !done() { try? await Task.sleep(for: .milliseconds(10)) }
    }

    @Test func aPlaylistMadeElsewhereTurnsUp() async {
        let server = Server()
        let music = client(server)
        let start = Date.now
        music.warmOwnPlaylists(videoId: "v1", now: start)
        await settle(until: { !music.ownPlaylists.isEmpty })
        #expect(music.ownPlaylists.map(\.id) == ["PLa"])

        server.playlists.append(("PLb", "made on the phone"))
        music.warmOwnPlaylists(videoId: "v2", now: start.addingTimeInterval(60))
        await settle(until: { server.asked > 1 })
        #expect(server.asked == 1, "a list a minute old is used as it is: every song change and hover warms it")

        music.warmOwnPlaylists(videoId: "v3", now: start.addingTimeInterval(6 * 60))
        #expect(music.ownPlaylists.map(\.id) == ["PLa"], "the old list stays in the menu while the new one comes")
        await settle(until: { music.ownPlaylists.count == 2 })
        #expect(music.ownPlaylists.map(\.id) == ["PLa", "PLb"])
    }

    @Test func anotherAccountsPlaylistsArentOffered() async {
        let key = "accountPageId"
        let saved = UserDefaults.standard.object(forKey: key)
        defer { if let saved { UserDefaults.standard.set(saved, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) } }
        let server = Server()
        let music = client(server)
        music.warmOwnPlaylists(videoId: "v1")
        await settle(until: { !music.ownPlaylists.isEmpty })

        music.switchAccount(pageId: "brand")
        #expect(music.ownPlaylists.isEmpty, "the old account's playlists go with it")
        #expect(music.addedTo.isEmpty)
        server.playlists = [("PLbrand", "brand's")]
        music.warmOwnPlaylists(videoId: "v1")
        await settle(until: { !music.ownPlaylists.isEmpty })
        #expect(music.ownPlaylists.map(\.id) == ["PLbrand"])
    }
}
