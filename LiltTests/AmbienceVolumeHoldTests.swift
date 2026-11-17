import Foundation
import Testing
import WebKit
@testable import Lilt

/// A sound starts at the level the drawer shows (its own level under the bed's), not at YouTube
/// Music's: the page sets its own volume as the track starts, and it mustn't win. This plays a
/// real ambience page, quietly, in the signed-in test host.
@MainActor
struct AmbienceVolumeHoldTests {
    @Test func aSoundStartsAtItsLevel() async throws {
        let delegate = try #require(AppDelegate.shared)

        var pages: [any PlayerBridging] = []
        let ambience = AmbienceService(defaults: isolatedDefaults("AmbienceVolumeHoldTests"))
        ambience.hostWebView = delegate.ambience.hostWebView
        let make = try #require(delegate.ambience.makePlayer)
        ambience.makePlayer = { let page = make(); pages.append(page); return page }
        ambience.volume = 0.08
        ambience.setLevel(0.5, for: .fire)
        defer { ambience.stopAll() }

        ambience.toggle(.fire)
        let view = try #require(pages.first?.webView)
        let expected = 0.04
        var heard: [Double] = []
        for second in 0..<25 {
            try? await Task.sleep(for: .seconds(1))
            let volume = try? await view.evaluateJavaScript("(() => { const v = document.querySelector('video'); return (v && !v.paused && v.currentTime > 0) ? v.volume : -1; })()") as? Double
            if let volume, volume >= 0 { heard.append(volume) }
            if second >= 20, heard.count >= 5 { break }
        }
        try #require(!heard.isEmpty, "the fire track never started playing")
        let wrong = heard.filter { abs($0 - expected) > 0.005 }
        #expect(wrong.isEmpty, "while playing, the page's volume was \(heard.map { String(format: "%.2f", $0) }) — should hold at \(expected)")
    }
}
