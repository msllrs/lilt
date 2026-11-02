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
    func queueNext(videoId: String, after sourceId: String) { calls.append("queueNext:\(videoId)>\(sourceId)") }
    func cancelQueueNext() { calls.append("cancelQueueNext") }
    /// The user agent the page was last given (it starts as Safari's, like the real one).
    private(set) var userAgent = InnerTubeClient.safariUserAgent
    func setUserAgent(_ userAgent: String) {
        guard userAgent != self.userAgent else { return }
        self.userAgent = userAgent
        calls.append(userAgent == InnerTubeClient.chromeUserAgent ? "userAgent:chrome" : "userAgent:safari")
    }
    func play() { calls.append("play") }
    func pause() { calls.append("pause") }
    func seek(to seconds: Double) { calls.append("seek") }
    func setVolume(_ volume: Double) {}
    func toggleLike() {}
    func unload() { calls.append("unload") }

    /// The page reporting `id` at `time` of a song `duration` long.
    func report(_ id: String, playing: Bool = true, time: Double = 1, duration: Double = 300) {
        onEvent?(.state(PlaybackSnapshot(
            videoId: id, isPlaying: playing, currentTime: time, duration: duration,
            title: id, artist: "Tool", artworkURL: nil,
            artistId: "UC1", albumId: "MPRE1", albumTitle: "Lateralus", likeStatus: nil
        )))
    }

    /// The last song asked for with `queueNext`, and the `load:` calls in order.
    var queuedNext: [String] { calls.filter { $0.hasPrefix("queueNext:") }.map { String($0.dropFirst("queueNext:".count)) } }
    var loads: [String] { calls.filter { $0.hasPrefix("load:") }.map { String($0.dropFirst("load:".count)) } }
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
