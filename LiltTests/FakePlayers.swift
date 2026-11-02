import Foundation
import WebKit
@testable import Lilt

/// A web player that only records what it was asked to do, and plays the page's side of the
/// conversation when a test says so.
@MainActor
final class FakeBridge: PlayerBridging {
    var onEvent: ((PlayerEvent) -> Void)?
    var webView: WKWebView? { nil }
    private(set) var calls: [String] = []

    func warmUp() { calls.append("warmUp") }
    func load(videoId: String) { calls.append("load:\(videoId)") }
    func cue(videoId: String) { calls.append("cue:\(videoId)") }
    func hold() { calls.append("hold") }
    func start() { calls.append("start") }
    func play() { calls.append("play") }
    func pause() { calls.append("pause") }
    func seek(to seconds: Double) { calls.append("seek") }
    func setVolume(_ volume: Double) {}
    func toggleLike() {}
    func unload() { calls.append("unload") }

    /// The page reporting `id` playing at `time`.
    func report(_ id: String, playing: Bool = true, time: Double = 1) {
        onEvent?(.state(PlaybackSnapshot(
            videoId: id, isPlaying: playing, currentTime: time, duration: 300,
            title: id, artist: "Tool", artworkURL: nil,
            artistId: "UC1", albumId: "MPRE1", albumTitle: "Lateralus", likeStatus: nil
        )))
    }
}

/// Every fake the player made, in order: the first is the one it starts with.
@MainActor
final class FakePlayers {
    var all: [FakeBridge] = []
    var first: FakeBridge { all[0] }
    var second: FakeBridge? { all.count > 1 ? all[1] : nil }

    /// Presses play on the restored song and has the page report it under way.
    func startPlaying(_ player: PlayerService) {
        player.resume()
        first.report(player.current!.id)
    }
}

/// A player resumed on `queue[0]` (seeded through the saved `playbackState`) with fake web
/// players and the gapless mode given, or the old switch's value to migrate from. The real
/// app's saved playback and setting are put back afterwards.
@MainActor
func withFakePlayer(
    _ queue: [Track], gapless: PlayerService.GaplessMode, legacySwitch: Bool? = nil,
    _ body: (PlayerService, FakePlayers) async throws -> Void
) async throws {
    let keys = ["playbackState", PlayerService.gaplessKey, PlayerService.gaplessModeKey]
    let saved = keys.map { UserDefaults.standard.object(forKey: $0) }
    defer {
        for (key, value) in zip(keys, saved) {
            if let value { UserDefaults.standard.set(value, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
        }
    }
    let state: [String: Any] = ["queue": try JSONSerialization.jsonObject(with: JSONEncoder().encode(queue)), "index": 0, "time": 0]
    UserDefaults.standard.set(try JSONSerialization.data(withJSONObject: state), forKey: "playbackState")
    if let legacySwitch {
        UserDefaults.standard.removeObject(forKey: PlayerService.gaplessModeKey)
        UserDefaults.standard.set(legacySwitch, forKey: PlayerService.gaplessKey)
    } else {
        UserDefaults.standard.set(gapless.rawValue, forKey: PlayerService.gaplessModeKey)
    }
    let fakes = FakePlayers()
    let player = PlayerService(auth: AuthService(), makeBridge: {
        let fake = FakeBridge()
        fakes.all.append(fake)
        return fake
    })
    try await body(player, fakes)
}
