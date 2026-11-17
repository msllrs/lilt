import Foundation
import Testing
import WebKit
@testable import Lilt

/// The observer script reports the player's state to Lilt as the song plays. It runs in both web
/// views, the one you hear and the standby that holds the next song for gapless playback, and
/// each report wakes Lilt's main thread to decode and apply it. The held standby's reports are
/// thrown away, so it sends none of its own; the playing page sends one about twice a second,
/// its once-a-second check adding nothing on top of the playhead's.
@MainActor
struct PlayerReportRateTests {
    private final class Recorder: NSObject, WKScriptMessageHandler {
        var types: [String] = []
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            if let body = message.body as? [String: Any], let type = body["type"] as? String { types.append(type) }
        }
        var stateUpdates: Int { types.filter { $0 == "STATE_UPDATE" }.count }
    }

    /// The script in a page of its own with a bare `<video>` in it, off the app's web data.
    private static func page() async throws -> (WKWebView, Recorder) {
        let recorder = Recorder()
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        // Out of sight a web view's timers are slowed; the script's once-a-second check is one.
        config.preferences.inactiveSchedulingPolicy = .none
        config.userContentController.add(recorder, name: "lilt")
        config.userContentController.addUserScript(
            WKUserScript(source: PlayerObserverScript.source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 200, height: 200), configuration: config)
        web.loadHTMLString("<html><body><video></video></body></html>", baseURL: URL(string: "https://lilt.test/watch?v=abc"))
        let deadline = Date.now.addingTimeInterval(10)
        while !recorder.types.contains("READY") {
            try #require(Date.now < deadline, "the script never said READY")
            try await Task.sleep(for: .milliseconds(50))
        }
        return (web, recorder)
    }

    @Test func aHeldStandbyReportsNothing() async throws {
        let (web, recorder) = try await Self.page()
        _ = try await web.evaluateJavaScript("window.__lilt.hold(); 0")
        let before = recorder.stateUpdates
        try await Task.sleep(for: .milliseconds(3200))
        #expect(recorder.stateUpdates - before == 0)
    }

    /// Paused, nothing moves the playhead, and the once-a-second check is what carries a like or a
    /// title the page fills in late.
    @Test func aPausedPageStillReportsOnceASecond() async throws {
        let (web, recorder) = try await Self.page()
        let before = recorder.stateUpdates
        try await Task.sleep(for: .milliseconds(3200))
        withExtendedLifetime(web) {}
        #expect((2...4).contains(recorder.stateUpdates - before), "\(recorder.stateUpdates - before) reports in 3.2s")
    }

    /// The playhead moving (the element's `timeupdate`, fired here ten times a second)
    /// reports at most every half second; the once-a-second check doesn't report again between.
    @Test func aPlayingPageReportsAboutTwiceASecond() async throws {
        let (web, recorder) = try await Self.page()
        // Fired from here: the page's own timers run slow in a web view out of sight.
        let before = recorder.stateUpdates
        let start = Date.now
        while Date.now.timeIntervalSince(start) < 4 {
            _ = try await web.evaluateJavaScript("document.querySelector('video').dispatchEvent(new Event('timeupdate')); 0")
            try await Task.sleep(for: .milliseconds(100))
        }
        let sent = recorder.stateUpdates - before
        // Four seconds at two a second, give or take one at either end.
        #expect(sent <= 9, "\(sent) reports in 4s")
        #expect(sent >= 6, "\(sent) reports in 4s")
    }
}
