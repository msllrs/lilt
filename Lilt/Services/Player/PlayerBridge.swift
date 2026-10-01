import Foundation
import WebKit

struct PlaybackSnapshot: Sendable {
    var videoId: String?
    var isPlaying: Bool
    var currentTime: Double
    var duration: Double
    var title: String
    var artist: String
    var artworkURL: URL?
}

enum PlayerEvent {
    case ready
    case state(PlaybackSnapshot)
    case ended(videoId: String?)
}

/// Owns the hidden `WKWebView` that actually plays audio and translates its script messages into
/// `PlayerEvent`s. WebKit handles DRM; this type only drives and observes it.
@MainActor
final class PlayerBridge: NSObject {
    let webView: WKWebView
    var onEvent: ((PlayerEvent) -> Void)?

    private static let handlerName = "lilt"
    private static let world: WKContentWorld = .defaultClient

    init(dataStore: WKWebsiteDataStore) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = dataStore
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsAirPlayForMediaPlayback = true
        config.userContentController.addUserScript(
            WKUserScript(
                source: PlayerObserverScript.source,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true,
                in: Self.world
            )
        )
        webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = InnerTubeClient.safariUserAgent
        #if DEBUG
        webView.isInspectable = true
        #endif
        super.init()
        config.userContentController.add(MessageProxy(bridge: self), contentWorld: Self.world, name: Self.handlerName)
    }

    func load(videoId: String) {
        let url = "https://music.youtube.com/watch?v=\(videoId)"
        if webView.url?.host == "music.youtube.com" {
            // Replace instead of push so WebKit's history never grows.
            call("location.replace(\(Self.quote(url)))")
        } else {
            webView.load(URLRequest(url: URL(string: url)!))
        }
    }

    func play() { call("window.__lilt && window.__lilt.play()") }
    func pause() { call("window.__lilt && window.__lilt.pause()") }
    func seek(to seconds: Double) { call("window.__lilt && window.__lilt.seek(\(seconds))") }
    func setVolume(_ volume: Double) { call("window.__lilt && window.__lilt.setVolume(\(volume))") }
    func unload() { webView.load(URLRequest(url: URL(string: "about:blank")!)) }

    private func call(_ js: String) {
        webView.evaluateJavaScript(js, in: nil, in: Self.world) { _ in }
    }

    private static func quote(_ s: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: [s])
        let encoded = data.flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
        return String(encoded.dropFirst().dropLast())
    }

    fileprivate func receive(_ body: [String: Any]) {
        switch body["type"] as? String {
        case "READY":
            onEvent?(.ready)
        case "TRACK_ENDED":
            onEvent?(.ended(videoId: body["videoId"] as? String))
        case "STATE_UPDATE":
            let snapshot = PlaybackSnapshot(
                videoId: body["videoId"] as? String,
                isPlaying: body["isPlaying"] as? Bool ?? false,
                currentTime: body["currentTime"] as? Double ?? 0,
                duration: body["duration"] as? Double ?? 0,
                title: body["title"] as? String ?? "",
                artist: body["artist"] as? String ?? "",
                artworkURL: (body["artworkURL"] as? String).flatMap { $0.isEmpty ? nil : URL(string: $0) }
            )
            onEvent?(.state(snapshot))
        default:
            break
        }
    }
}

/// Breaks the retain cycle between the user content controller and the bridge.
@MainActor
private final class MessageProxy: NSObject, WKScriptMessageHandler {
    weak var bridge: PlayerBridge?

    init(bridge: PlayerBridge) { self.bridge = bridge }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        bridge?.receive(body)
    }
}
