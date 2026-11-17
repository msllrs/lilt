import Foundation
import Testing
@testable import Lilt

/// A like from a row's menu that YouTube Music didn't take says so: the notice that said Liked
/// (or Removed) turns into Couldn't like (or Couldn't remove), and the row's like goes back to
/// what it was. The playing song is liked through the page's own button and isn't covered here.
@MainActor
struct LikeFailureTests {
    private let forty = Track(id: "ZLDUbN0Gp2M", title: "Forty Six & 2", artist: "Tool")
    private let schism = Track(id: "tuw1ziytBDk", title: "Schism", artist: "Tool")

    private func withPlayer(_ body: (PlayerService) async throws -> Void) async throws {
        let key = "playbackState"
        let playhead = SavedPlayhead()
        defer { playhead.restore() }
        let saved = UserDefaults.standard.data(forKey: key)
        defer { if let saved { UserDefaults.standard.set(saved, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) } }
        let state: [String: Any] = ["queue": try JSONSerialization.jsonObject(with: JSONEncoder().encode([forty])), "index": 0, "time": 0]
        UserDefaults.standard.set(try JSONSerialization.data(withJSONObject: state), forKey: key)
        try await body(PlayerService(auth: AuthService(), makeBridge: { FakeBridge() }))
    }

    private func settle(until done: () -> Bool) async {
        for _ in 0..<50 where !done() { try? await Task.sleep(for: .milliseconds(10)) }
    }

    @Test func aLikeThatDidntTakeSaysSo() async throws {
        try await withPlayer { player in
            let music = YTMusicClient(auth: AuthService(), write: { _, _ in throw URLError(.notConnectedToInternet) }, persists: false)
            let center = NoticeCenter(clock: ManualNoticeClock())
            RowMenu.setLiked(true, schism, player: player, music: music, notices: center)
            #expect(center.current?.spoken == "Liked Schism", "the like answers the click at once")
            await settle(until: { center.current?.spoken != "Liked Schism" })
            #expect(center.current?.spoken == "Couldn't like Schism")
            #expect(music.isLiked(schism) == nil, "the row's like is back to what it was")
        }
    }

    @Test func anUnlikeThatDidntTakeSaysSo() async throws {
        try await withPlayer { player in
            let music = YTMusicClient(auth: AuthService(), write: { _, _ in throw URLError(.timedOut) }, persists: false)
            let center = NoticeCenter(clock: ManualNoticeClock())
            RowMenu.setLiked(false, schism, player: player, music: music, notices: center)
            await settle(until: { center.current?.spoken.hasPrefix("Couldn't") == true })
            #expect(center.current?.spoken == "Couldn't remove Schism from Liked")
        }
    }

    @Test func aLikeThatTookStaysLiked() async throws {
        try await withPlayer { player in
            let music = YTMusicClient(auth: AuthService(), write: { _, _ in JSONObject(value: [:]) }, persists: false)
            let center = NoticeCenter(clock: ManualNoticeClock())
            RowMenu.setLiked(true, schism, player: player, music: music, notices: center)
            try await Task.sleep(for: .milliseconds(100))
            #expect(center.current?.spoken == "Liked Schism")
            #expect(music.isLiked(schism) == true)
        }
    }
}
