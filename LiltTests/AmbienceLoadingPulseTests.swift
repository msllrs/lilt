import Foundation
import Testing
import WebKit
@testable import Lilt

/// A sound's button pulses while its page loads and stops once the sound is playing. This plays a
/// real ambience page, quietly, in the signed-in test host.
@MainActor
struct AmbienceLoadingPulseTests {
    @Test func thePulseStopsOnceTheSoundPlays() async throws {
        let delegate = try #require(AppDelegate.shared)

        var pages: [any PlayerBridging] = []
        let ambience = AmbienceService(defaults: isolatedDefaults("AmbienceLoadingPulseTests"))
        ambience.hostWebView = delegate.ambience.hostWebView
        let make = try #require(delegate.ambience.makePlayer)
        ambience.makePlayer = { let page = make(); pages.append(page); return page }
        ambience.volume = 0.04
        defer { ambience.stopAll() }

        ambience.toggle(.rain)
        #expect(ambience.loading == [.rain], "pulses while its page loads")
        let view = try #require(pages.first?.webView)
        var playingAt: Int?
        for second in 0..<20 {
            try? await Task.sleep(for: .seconds(1))
            let playing = try? await view.evaluateJavaScript("(() => { const v = document.querySelector('video'); return !!(v && !v.paused && v.currentTime > 0.5); })()") as? Bool
            if playing == true, playingAt == nil { playingAt = second }
            // Give the app a couple of seconds after the sound is audible.
            if let playingAt, second >= playingAt + 2 { break }
        }
        try #require(playingAt != nil, "the rain track never started playing")
        #expect(ambience.loading.isEmpty, "rain has been playing since \(playingAt ?? -1)s, but its button still pulses")
    }
}
