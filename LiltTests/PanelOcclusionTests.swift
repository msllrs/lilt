import AppKit
import Testing
@testable import Lilt

/// The discs, notes and marquees pause whenever none of the panel can be seen, not only when
/// Lilt hides it itself: hidden with the app (⌘H), covered, or on another Space, the window's
/// timelines kept ticking thirty times a second and every tick re-ran the whole view graph.
@MainActor
struct PanelOcclusionTests {
    /// Waits for the window server to report the change, which lands a run-loop turn or more later.
    private func settle(_ done: () -> Bool) async {
        for _ in 0..<40 where !done() { try? await Task.sleep(for: .milliseconds(50)) }
    }

    @Test func aWindowOutOfSightParksThePanel() async throws {
        let navigation = NavigationModel()
        // Small and all but transparent, at the screen's corner: the window server still counts
        // it as on screen, but nobody sees a test flash by.
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 4, height: 4), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.alphaValue = 0.02
        let token = AppDelegate.followOcclusion(of: window, into: navigation)
        defer { NotificationCenter.default.removeObserver(token); window.orderOut(nil) }

        window.orderFrontRegardless()
        await settle { window.occlusionState.contains(.visible) }
        // Whether it can be seen depends on the real screen (another Space, a full-screen app);
        // without a sighting first, ordering it out changes nothing and proves nothing.
        try #require(window.occlusionState.contains(.visible), "the window server never showed the test window")
        #expect(!navigation.isPanelOutOfSight)

        // What hiding the app does to its windows.
        window.orderOut(nil)
        await settle { navigation.isPanelOutOfSight }
        #expect(navigation.isPanelOutOfSight)
        #expect(!navigation.isPanelHidden)

        window.orderFrontRegardless()
        await settle { !navigation.isPanelOutOfSight }
        #expect(!navigation.isPanelOutOfSight)
    }

    @Test func hidingThePanelParksItBeforeTheWindowServerReports() {
        let navigation = NavigationModel()
        navigation.isPanelHidden = true
        #expect(navigation.isPanelOutOfSight)
    }
}
