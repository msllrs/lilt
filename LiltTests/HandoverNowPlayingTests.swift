import Foundation
import Testing
import WebKit
@testable import Lilt

/// After a gapless handover, macOS Now Playing showed the new song's title and album but no
/// artwork, though the page's media session held four sizes of it (the diagnostics log, live).
/// The page that takes over spent the song before held silent, so WebKit never adopted its
/// session while YouTube Music filled the artwork in. Starting a held page clears its session's
/// metadata and gives it back the same object, so WebKit takes it afresh as on an ordinary
/// load, and YouTube Music, which fills that object in over the next seconds, still reaches it.
/// (A first fix set a copy instead: it caught the metadata half filled in and cut YouTube
/// Music's later updates off, so Now Playing lost the album too.)
///
/// This runs Lilt's page script in a real web view on a stand-in page with a media session,
/// and checks the script's side. That macOS then shows the artwork can only be seen live.
@MainActor
struct HandoverNowPlayingTests {
    private static let page = """
    <html><body><video></video><script>
    // YouTube Music's own metadata, half filled in as it is when a song starts sounding.
    window.firstMetadata = new MediaMetadata({
      title: 'RedRum', artist: 'HXG', album: '',
      artwork: [{ src: 'https://yt3.googleusercontent.com/cover=w60-h60', sizes: '60x60', type: 'image/jpeg' }],
    });
    navigator.mediaSession.metadata = window.firstMetadata;
    // Every value the session's metadata is set to, from here on.
    window.metadataSets = [];
    const proto = Object.getPrototypeOf(navigator.mediaSession);
    const property = Object.getOwnPropertyDescriptor(proto, 'metadata');
    Object.defineProperty(navigator.mediaSession, 'metadata', {
      get() { return property.get.call(this); },
      set(value) { window.metadataSets.push(value === null ? 'null' : value === window.firstMetadata ? 'same' : 'other'); property.set.call(this, value); },
      configurable: true,
    });
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

        let sets = try await view.evaluateJavaScript("window.metadataSets.join(',')") as? String
        #expect(sets?.hasPrefix("null,same") == true, "cleared, then given back YouTube Music's own object (\(sets ?? "nil"))")
        #expect(sets?.contains("other") == false, "never a copy in its place")
        let own = try await view.evaluateJavaScript("navigator.mediaSession.metadata === window.firstMetadata") as? Bool
        #expect(own == true)
        // YouTube Music finishing it off afterwards still reaches the session.
        let filled = try await view.evaluateJavaScript("window.firstMetadata.album = 'RedRum'; navigator.mediaSession.metadata.album") as? String
        #expect(filled == "RedRum")
    }
}
