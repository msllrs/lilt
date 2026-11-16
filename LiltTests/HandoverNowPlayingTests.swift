import Foundation
import Testing
import WebKit
@testable import Lilt

/// After a gapless handover, macOS Now Playing showed the new song's title and album but no
/// artwork, though the page's media session held four sizes of it (the diagnostics log, live).
/// The page that takes over spent the song before held silent, so WebKit never adopted its
/// session while YouTube Music filled the artwork in. Starting a held page sets its session's
/// metadata again once it's sounding, the same title, album and artwork, so WebKit takes it
/// as it does on an ordinary load.
///
/// This runs Lilt's page script in a real web view on a stand-in page with a media session,
/// and checks the script's side: the metadata is set anew, as it was. That macOS then shows
/// the artwork can only be seen in the running app.
@MainActor
struct HandoverNowPlayingTests {
    private static let page = """
    <html><body><video></video><script>
    navigator.mediaSession.metadata = new MediaMetadata({
      title: 'RedRum', artist: 'HXG', album: 'RedRum',
      artwork: [{ src: 'https://yt3.googleusercontent.com/cover=w544-h544', sizes: '544x544', type: 'image/jpeg' }],
    });
    window.firstMetadata = navigator.mediaSession.metadata;
    </script></body></html>
    """

    private final class Loaded: NSObject, WKNavigationDelegate {
        var done = false
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { done = true }
    }

    @Test func startingAHeldPageSetsItsSessionAgain() async throws {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.userContentController.addUserScript(WKUserScript(source: PlayerObserverScript.source, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .page))
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 100, height: 100), configuration: config)
        let loaded = Loaded()
        view.navigationDelegate = loaded
        view.loadHTMLString(Self.page, baseURL: URL(string: "https://music.youtube.com/"))
        for _ in 0..<100 where !loaded.done { try await Task.sleep(for: .milliseconds(20)) }
        try #require(loaded.done, "the stand-in page loads")
        // The script finds the page's <video> on its next tick.
        try await Task.sleep(for: .milliseconds(1200))

        // Held first, as a standby page is while the song before plays.
        _ = try await view.evaluateJavaScript("window.__lilt.hold(); window.__lilt.start(); true")
        try await Task.sleep(for: .milliseconds(2500))

        let renewed = try await view.evaluateJavaScript("navigator.mediaSession.metadata !== window.firstMetadata") as? Bool
        #expect(renewed == true, "the session's metadata is set again after the page starts")
        let kept = try await view.evaluateJavaScript("""
        (() => { const m = navigator.mediaSession.metadata;
          return [m.title, m.artist, m.album, m.artwork.length, m.artwork[0].src].join('|'); })()
        """) as? String
        #expect(kept == "RedRum|HXG|RedRum|1|https://yt3.googleusercontent.com/cover=w544-h544", "with the same title, album and artwork")
    }
}
