import Foundation
import Testing
@testable import Lilt

/// Play Next puts songs straight after the current one, ahead of anything already queued by
/// hand; Add to Queue puts them at the end of what's queued by hand.
@MainActor
struct PlayNextTests {
    private func song(_ id: String) -> Track { Track(id: id, title: id, artist: "Tool") }

    /// A player resumed on `queue[0]`, without loading anything into the web player. The real
    /// app's saved playback is put back afterwards.
    private func withPlayer(_ queue: [Track], _ body: (PlayerService) -> Void) throws {
        let key = "playbackState"
        let saved = UserDefaults.standard.data(forKey: key)
        defer { if let saved { UserDefaults.standard.set(saved, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) } }
        let state: [String: Any] = ["queue": try JSONSerialization.jsonObject(with: JSONEncoder().encode(queue)), "index": 0, "time": 0]
        UserDefaults.standard.set(try JSONSerialization.data(withJSONObject: state), forKey: key)
        body(PlayerService(auth: AuthService()))
    }

    @Test func playNextGoesAheadOfWhatsQueued() throws {
        try withPlayer([song("now"), song("list1"), song("list2")]) { player in
            player.enqueue(song("queued"))
            player.playNext([song("next1"), song("next2")])
            #expect(player.upcoming.map(\.id) == ["next1", "next2", "queued"])
            #expect(player.automaticUpcoming.map(\.id) == ["list1", "list2"])
        }
    }

    @Test func playNextWithNothingQueuedLeadsTheList() throws {
        try withPlayer([song("now"), song("list1")]) { player in
            player.playNext([song("next")])
            #expect(player.upcoming.map(\.id) == ["next"])
            #expect(player.automaticUpcoming.map(\.id) == ["list1"])
        }
    }
}
