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
    var artistId: String?
    var albumId: String?
    var albumTitle: String?
    /// "LIKE", "DISLIKE" or "INDIFFERENT" from the page's like button; nil when it wasn't found.
    var likeStatus: String?
}

enum PlayerEvent {
    case ready
    case state(PlaybackSnapshot)
    case ended(videoId: String?)
    /// The `<video>` has started producing sound (its `playing` event).
    case playing(videoId: String?)
    /// A standby page has the song held at 0:00, buffered, ready to `start`.
    case cued(videoId: String)
    /// A standby page couldn't get the song ready; it plays the ordinary way instead.
    case cueFailed(videoId: String)
    /// The page couldn't play `videoId`: the `<video>`'s `error`, the player's `onError`, or its
    /// error screen showing. `reason` says which, with the code.
    case playbackError(videoId: String?, reason: String)
    /// A Now Playing / media key command the page's media session forwarded to us.
    case remote(RemoteAction)
}

/// The page's media session actions Lilt takes over: next and previous drive Lilt's queue, and
/// pause and play come to Lilt so it knows when the system paused it (see `isPausedRemotely`).
enum RemoteAction: String {
    case next, previous, pause, play
}

/// What `PlayerService` needs from a web player, so tests can stand in a fake that never loads
/// a web view.
@MainActor
protocol PlayerBridging: AnyObject {
    var onEvent: ((PlayerEvent) -> Void)? { get set }
    /// The view to keep in a window while it plays; nil for a fake.
    var webView: WKWebView? { get }
    func warmUp()
    func load(videoId: String)
    /// Gapless playback: navigates to `videoId` held silent and paused at 0:00, and reports
    /// `.cued` once enough is buffered.
    func cue(videoId: String)
    /// Silences and pauses the page, and keeps it that way through whatever it autoplays.
    func hold()
    /// Plays the cued song at once, at YouTube's own volume.
    func start()
    func play()
    func pause()
    func seek(to seconds: Double)
    func setVolume(_ volume: Double)
    func toggleLike()
    func unload()
}

/// Owns the hidden `WKWebView` that actually plays audio and translates its script messages into
/// `PlayerEvent`s. WebKit handles DRM; this type only drives and observes it.
@MainActor
final class PlayerBridge: NSObject, PlayerBridging {
    private let view: WKWebView
    var webView: WKWebView? { view }
    var onEvent: ((PlayerEvent) -> Void)?
    /// What the diagnostics log calls this page ("web player 2"); the player names it.
    var logName = "web player"

    /// True once the observer script has announced itself in the current document.
    private var isReady = false
    /// A load requested while the document was still loading; sent on READY.
    private var pendingVideoId: String?
    /// The song being cued, until it's ready. Sent again on READY, so a cue survives the shell
    /// loading or the page's reload fallback.
    private var cueVideoId: String?

    private static let handlerName = "lilt"
    private static let world: WKContentWorld = .page

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
        view = WKWebView(frame: .zero, configuration: config)
        view.customUserAgent = InnerTubeClient.safariUserAgent
        #if DEBUG
        view.isInspectable = true
        #endif
        super.init()
        view.navigationDelegate = self
        config.userContentController.add(MessageProxy(bridge: self), contentWorld: Self.world, name: Self.handlerName)
    }

    /// Loads the YouTube Music shell ahead of time so the first track change is an in-app
    /// navigation rather than a cold page load.
    func warmUp() {
        guard !isShellLoaded else { return }
        view.load(URLRequest(url: URL(string: "https://music.youtube.com/")!))
    }

    func load(videoId: String) {
        cueVideoId = nil
        if isShellLoaded && isReady {
            call("window.__lilt && window.__lilt.navigate(\(Self.quote(videoId)))")
        } else if isShellLoaded {
            // The shell is mid-load (e.g. warm-up); hand the request to the script when it's up.
            pendingVideoId = videoId
        } else {
            pendingVideoId = nil
            view.load(URLRequest(url: URL(string: "https://music.youtube.com/watch?v=\(videoId)")!))
        }
    }

    func cue(videoId: String) {
        cueVideoId = videoId
        pendingVideoId = nil
        if isShellLoaded && isReady {
            call("window.__lilt && window.__lilt.cue(\(Self.quote(videoId)))")
        } else if !isShellLoaded {
            // The shell, not the watch page: it doesn't autoplay, and READY sends the cue.
            view.load(URLRequest(url: URL(string: "https://music.youtube.com/")!))
        }
    }

    func hold() { call("window.__lilt && window.__lilt.hold()") }

    func start() {
        cueVideoId = nil
        call("window.__lilt && window.__lilt.start()")
    }

    private var isShellLoaded: Bool { view.url?.host == "music.youtube.com" }

    func play() { call("window.__lilt && window.__lilt.play()") }
    func pause() { call("window.__lilt && window.__lilt.pause()") }
    func seek(to seconds: Double) { call("window.__lilt && window.__lilt.seek(\(seconds))") }
    func setVolume(_ volume: Double) { call("window.__lilt && window.__lilt.setVolume(\(volume))") }
    func toggleLike() { call("window.__lilt && window.__lilt.toggleLike()") }
    func unload() {
        cueVideoId = nil
        pendingVideoId = nil
        view.load(URLRequest(url: URL(string: "about:blank")!))
    }

    private func call(_ js: String) {
        view.evaluateJavaScript(js, in: nil, in: Self.world) { _ in }
    }

    private static func quote(_ s: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: [s])
        let encoded = data.flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
        return String(encoded.dropFirst().dropLast())
    }

    fileprivate func receive(_ body: [String: Any]) {
        switch body["type"] as? String {
        case "READY":
            isReady = true
            if let videoId = pendingVideoId {
                pendingVideoId = nil
                load(videoId: videoId)
            } else if let videoId = cueVideoId {
                cue(videoId: videoId)
            }
            onEvent?(.ready)
        case "NAV":
            #if DEBUG
            DebugLog.player("Lilt navigation via \(body["method"] as? String ?? "?") for \(body["id"] as? String ?? "?")")
            #endif
        case "REMOTE":
            if let action = (body["action"] as? String).flatMap(RemoteAction.init(rawValue:)) {
                onEvent?(.remote(action))
            }
        case "TRACK_ENDED":
            onEvent?(.ended(videoId: body["videoId"] as? String))
        case "GAPLESS_PROBE":
            #if DEBUG
            if body["player"] as? Bool == true {
                DebugLog.player("Lilt gapless: probe (\(body["why"] as? String ?? "?")) #movie_player supportsGaplessAudio()=\(body["supportsGaplessAudio"] as? String ?? "?"), player APIs [\(body["apis"] as? String ?? "")], internal APIs [\(body["internalApis"] as? String ?? "")], UA \(body["userAgent"] as? String ?? "?")")
            } else {
                DebugLog.player("Lilt gapless: probe (\(body["why"] as? String ?? "?")) found no #movie_player")
            }
            #endif
        case "PLAYING":
            onEvent?(.playing(videoId: body["videoId"] as? String))
        case "SESSION":
            let fields = ["videoId", "title", "artist", "album", "artwork", "artworkSrc", "actions", "playbackState", "muted", "hold"]
                .map { "\($0)=\(body[$0].map { "\($0)" } ?? "nil")" }
            Diagnostics.shared.record(.player, "media session of \(logName) (\(body["when"] as? String ?? "?")): " + fields.joined(separator: " "))
        case "PLAYBACK_ERROR":
            onEvent?(.playbackError(videoId: body["videoId"] as? String, reason: body["reason"] as? String ?? "?"))
        case "CUED":
            guard let videoId = body["videoId"] as? String, videoId == cueVideoId else {
                #if DEBUG
                DebugLog.player("Lilt gapless: page CUED \(body["videoId"] as? String ?? "nil") dropped, cueing \(cueVideoId ?? "nothing")")
                #endif
                return
            }
            cueVideoId = nil
            onEvent?(.cued(videoId: videoId))
        case "CUE_FAILED":
            guard let videoId = body["videoId"] as? String, videoId == cueVideoId else {
                #if DEBUG
                DebugLog.player("Lilt gapless: page CUE_FAILED \(body["videoId"] as? String ?? "nil") dropped, cueing \(cueVideoId ?? "nothing")")
                #endif
                return
            }
            cueVideoId = nil
            onEvent?(.cueFailed(videoId: videoId))
        case "STATE_UPDATE":
            let snapshot = PlaybackSnapshot(
                videoId: body["videoId"] as? String,
                isPlaying: body["isPlaying"] as? Bool ?? false,
                currentTime: body["currentTime"] as? Double ?? 0,
                duration: body["duration"] as? Double ?? 0,
                title: body["title"] as? String ?? "",
                artist: body["artist"] as? String ?? "",
                artworkURL: (body["artworkURL"] as? String).flatMap { $0.isEmpty ? nil : URL(string: $0) },
                artistId: (body["artistId"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                albumId: (body["albumId"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                albumTitle: (body["albumTitle"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                likeStatus: (body["likeStatus"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            )
            onEvent?(.state(snapshot))
        default:
            break
        }
    }
}

extension PlayerBridge: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isReady = false
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


