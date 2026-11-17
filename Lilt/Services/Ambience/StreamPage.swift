import Foundation
import WebKit

/// What a feed's page reports back: it has started to sound, it is waiting for more of the
/// stream, or it gave up.
enum StreamEvent: Equatable {
    case playing
    case waiting
    case failed(String)
}

/// A feed's page. What `AmbienceService` needs, so tests can stand in for the web view.
@MainActor
protocol StreamPaging: AnyObject {
    var webView: WKWebView? { get }
    var onEvent: ((StreamEvent) -> Void)? { get set }
    func load(_ url: URL, volume: Float)
    func setVolume(_ volume: Float)
    func stop()
}

/// The live feed's page: a hidden web view holding one `<audio>` element.
///
/// Not AVPlayer. Before it will read an MP3 over HTTP, AVFoundation asks the server for
/// `Range: bytes=0-1`; LiveATC ignores the range and answers with the whole stream, so
/// AVFoundation finds no track and plays the item as silence while reporting it as playing
/// (the drawer's lit plane with nothing behind it). WebKit reads these mounts the way a
/// browser does, which is how the hosts serve them.
@MainActor
final class StreamPage: NSObject, StreamPaging, WKNavigationDelegate {
    var webView: WKWebView? { view }
    var onEvent: ((StreamEvent) -> Void)?

    private let view: WKWebView
    /// The level the page should be at, kept so a reload or a new document starts at it.
    private var volume: Float = 1

    private static let handlerName = "lilt"
    private static let world: WKContentWorld = .page

    override init() {
        let config = WKWebViewConfiguration()
        // The drawer's click is the gesture; the stream starts on its own, as the sounds do.
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsAirPlayForMediaPlayback = false
        config.userContentController.addUserScript(
            WKUserScript(source: Self.inertMediaSession, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: Self.world)
        )
        view = WKWebView(frame: .zero, configuration: config)
        super.init()
        view.navigationDelegate = self
        config.userContentController.add(MessageProxy(page: self), contentWorld: Self.world, name: Self.handlerName)
    }

    func load(_ url: URL, volume: Float) {
        self.volume = volume
        let html = """
        <!doctype html><meta charset="utf-8">
        <audio id="a" preload="auto"></audio>
        <script>
        const a = document.getElementById('a');
        const send = (event, extra) => window.webkit.messageHandlers.\(Self.handlerName).postMessage(Object.assign({ event }, extra || {}));
        a.volume = \(volume);
        a.addEventListener('playing', () => send('playing'));
        a.addEventListener('waiting', () => send('waiting'));
        a.addEventListener('stalled', () => send('waiting'));
        a.addEventListener('error', () => send('error', { message: a.error ? a.error.code + ': ' + a.error.message : 'unknown' }));
        a.src = \(Self.quote(url.absoluteString));
        a.play().catch(e => send('error', { message: String(e) }));
        </script>
        """
        view.loadHTMLString(html, baseURL: nil)
    }

    func setVolume(_ volume: Float) {
        self.volume = volume
        view.evaluateJavaScript("document.getElementById('a').volume = \(volume)")
    }

    func stop() {
        onEvent = nil
        view.evaluateJavaScript("document.getElementById('a').pause()")
        view.stopLoading()
        view.removeFromSuperview()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // A new document starts at its own volume; put the drawer's back.
        setVolume(volume)
    }

    fileprivate func receive(_ body: [String: Any]) {
        switch body["event"] as? String {
        case "playing": onEvent?(.playing)
        case "waiting": onEvent?(.waiting)
        case "error": onEvent?(.failed(body["message"] as? String ?? "unknown"))
        default: break
        }
    }

    /// The page's Media Session, made inert before its scripts run, so the feed stays out of
    /// Now Playing and the media keys: it is a bed under the music, not a song.
    private static let inertMediaSession = """
    (() => {
      const inert = { metadata: null, playbackState: 'none', setActionHandler() {}, setPositionState() {} };
      try { Object.defineProperty(navigator, 'mediaSession', { value: inert, configurable: true }); } catch (e) {}
    })();
    """

    /// `string` as a JavaScript string literal, quotes and all.
    private static func quote(_ string: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [string]),
              let array = String(data: data, encoding: .utf8)
        else { return "\"\"" }
        return String(array.dropFirst().dropLast())
    }

    private final class MessageProxy: NSObject, WKScriptMessageHandler {
        weak var page: StreamPage?

        init(page: StreamPage) { self.page = page }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any] else { return }
            page?.receive(body)
        }
    }
}
