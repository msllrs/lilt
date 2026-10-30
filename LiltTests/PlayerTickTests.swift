import Foundation
import Observation
import Testing
@testable import Lilt

/// The web player reports its state several times a second. A report that says what the player
/// already shows must not notify anything observing it, or every row in every list on the
/// navigation stack is invalidated on each tick. `@Observable` skips the notification for an
/// equal value of an `Equatable` property, so `apply` can assign freely; this holds it to that,
/// should a property ever take a type that isn't `Equatable`.
@MainActor
struct PlayerTickTests {
    private let song = Track(id: "now", title: "Sober", artist: "Tool")

    /// A player resumed on `song`, without loading anything into the web player. The real
    /// app's saved playback is put back afterwards.
    private func withPlayer(_ body: (PlayerService) -> Void) throws {
        let key = "playbackState"
        let saved = UserDefaults.standard.data(forKey: key)
        defer { if let saved { UserDefaults.standard.set(saved, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) } }
        let state: [String: Any] = ["queue": try JSONSerialization.jsonObject(with: JSONEncoder().encode([song])), "index": 0, "time": 0]
        UserDefaults.standard.set(try JSONSerialization.data(withJSONObject: state), forKey: key)
        body(PlayerService(auth: AuthService()))
    }

    private func snapshot(time: Double = 12, playing: Bool = true, like: String = "LIKE") -> PlaybackSnapshot {
        PlaybackSnapshot(
            videoId: song.id, isPlaying: playing, currentTime: time, duration: 300,
            title: "Sober", artist: "Tool", artworkURL: URL(string: "https://lh3.googleusercontent.com/cover"),
            artistId: "UC1", albumId: "MPRE1", albumTitle: "Undertow", likeStatus: like
        )
    }

    /// Feeds `s` to the player the way the web view does, through the bridge.
    private func receive(_ s: PlaybackSnapshot, _ player: PlayerService) {
        player.bridge.onEvent?(.state(s))
    }

    /// Whether `action` notifies an observer that read `property`.
    private func notifies(_ property: (PlayerService) -> Void, on player: PlayerService, when action: () -> Void) -> Bool {
        final class Flag: @unchecked Sendable { var fired = false }
        let flag = Flag()
        withObservationTracking { property(player) } onChange: { flag.fired = true }
        action()
        return flag.fired
    }

    private var properties: [(String, (PlayerService) -> Void)] {
        [
            ("isPlaying", { _ = $0.isPlaying }),
            ("current", { _ = $0.current }),
            ("currentIndex", { _ = $0.currentIndex }),
            ("queue", { _ = $0.queue }),
            ("duration", { _ = $0.duration }),
            ("liveTitle", { _ = $0.liveTitle }),
            ("liveArtist", { _ = $0.liveArtist }),
            ("liveArtworkURL", { _ = $0.liveArtworkURL }),
            ("isLiked", { _ = $0.isLiked }),
        ]
    }

    @Test func anUnchangedReportNotifiesNothingButTheTime() throws {
        try withPlayer { player in
            receive(snapshot(), player)
            for (name, read) in properties {
                let fired = notifies(read, on: player) { receive(snapshot(time: 12.25), player) }
                #expect(!fired, "\(name) notified on an unchanged report")
            }
            #expect(notifies({ _ = $0.currentTime }, on: player) { receive(snapshot(time: 12.5), player) })
        }
    }

    @Test func aRealChangeStillNotifies() throws {
        try withPlayer { player in
            receive(snapshot(), player)
            #expect(notifies({ _ = $0.isPlaying }, on: player) { receive(snapshot(playing: false), player) })
            #expect(!player.isPlaying)
            #expect(notifies({ _ = $0.isLiked }, on: player) { receive(snapshot(playing: false, like: "INDIFFERENT"), player) })
            #expect(!player.isLiked)
        }
    }
}
