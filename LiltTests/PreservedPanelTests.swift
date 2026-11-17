import AppKit
import Testing
@testable import Lilt

/// Tests that drive the test host's own panel put it back as it was, and the window frame the
/// real app reads at launch with it, even when two of them run at once, as Swift Testing runs a
/// suite's tests: one collapsing to the mini player while another is putting the panel back
/// left the panel in mini and its saved frame at the platter's height, about 180 points, so the
/// real app came back from a test run as a strip.
@MainActor
struct PreservedPanelTests {
    private static let frameKey = "NSWindow Frame \(PanelWindow.autosaveName)"

    @Test func twoPanelTestsAtOnceLeaveThePanelAsItWas() async throws {
        let delegate = try #require(AppDelegate.shared)
        let defaults = UserDefaults.standard
        let savedFrame = defaults.string(forKey: Self.frameKey)
        let (wasMini, height) = (delegate.navigation.isMiniPlayer, delegate.panelFrame.height)
        // Each collapses to the mini player, the way the platter's double-click tests do, the
        // second starting while the first has the panel in mini.
        func collapse(after delay: Int) async throws {
            try? await Task.sleep(for: .milliseconds(delay))
            try await withPreservedPanel(delegate) {
                delegate.setMiniPlayer(true)
                for _ in 0..<25 { try? await Task.sleep(for: .milliseconds(20)) }
                #expect(delegate.navigation.isMiniPlayer)
            }
        }
        async let first: Void = collapse(after: 0)
        async let second: Void = collapse(after: 300)
        _ = try await (first, second)
        // Anything still moving lands, and saves the frame as it does.
        for _ in 0..<50 { try? await Task.sleep(for: .milliseconds(20)) }
        #expect(delegate.navigation.isMiniPlayer == wasMini, "the panel should be back as it was (mini \(wasMini)), not \(delegate.navigation.isMiniPlayer)")
        #expect(delegate.panelFrame.height == height, "the panel should be back at \(height)pt tall, not \(delegate.panelFrame.height)")
        #expect(defaults.string(forKey: Self.frameKey) == savedFrame, "the saved frame should be the real app's \(savedFrame ?? "none"), not \(defaults.string(forKey: Self.frameKey) ?? "none")")
    }
}
