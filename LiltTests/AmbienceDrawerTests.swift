import AppKit
import Testing
@testable import Lilt

/// In mini the window is the platter, so opening the ambience drawer must grow the window by
/// exactly what the platter grows by; short, and the platter's top is pushed out of the window.
@MainActor
struct AmbienceDrawerTests {
    private func settle(_ frames: Int) async { for _ in 0..<frames { try? await Task.sleep(for: .milliseconds(20)) } }

    @Test func miniWindowGrowsForTheDrawer() async throws {
        let delegate = try #require(AppDelegate.shared)
        let wasMini = delegate.navigation.isMiniPlayer
        let hadDrawer = delegate.navigation.isAmbienceVisible
        defer { Task { @MainActor in delegate.setAmbienceVisible(hadDrawer); delegate.setMiniPlayer(wasMini) } }
        delegate.setAmbienceVisible(false)
        delegate.setMiniPlayer(true)
        await settle(30)
        let before = delegate.panelFrame.height
        let platterBefore = delegate.navigation.platterHeight
        delegate.setAmbienceVisible(true)
        await settle(40)
        let after = delegate.panelFrame.height
        let platterAfter = delegate.navigation.platterHeight
        print("AXD window \(before) -> \(after), platter \(platterBefore) -> \(platterAfter), base \(delegate.navigation.platterBaseHeight), drawer \(AmbiencePanel.height)")
        #expect(after - before > AmbiencePanel.height - 2, "the window should grow by the drawer; grew \(after - before)")
        #expect(after >= platterAfter - 1, "the platter (\(platterAfter)) must fit the window (\(after))")
    }

    @Test func miniWindowGrowsForTheDrawerWithTheQueueOpen() async throws {
        let delegate = try #require(AppDelegate.shared)
        let wasMini = delegate.navigation.isMiniPlayer
        let hadDrawer = delegate.navigation.isAmbienceVisible
        let hadQueue = delegate.navigation.isQueueVisible
        defer { Task { @MainActor in delegate.setAmbienceVisible(hadDrawer); delegate.setQueueVisible(hadQueue); delegate.setMiniPlayer(wasMini) } }
        delegate.setAmbienceVisible(false)
        delegate.setMiniPlayer(true)
        await settle(30)
        delegate.setQueueVisible(true)
        await settle(40)
        let before = delegate.panelFrame.height
        let platterBefore = delegate.navigation.platterHeight
        delegate.setAmbienceVisible(true)
        await settle(40)
        let after = delegate.panelFrame.height
        let platterAfter = delegate.navigation.platterHeight
        print("AXD queue open: window \(before) -> \(after), platter \(platterBefore) -> \(platterAfter), base \(delegate.navigation.platterBaseHeight)")
        #expect(after - before > AmbiencePanel.height - 2, "the window should grow by the drawer; grew \(after - before)")
        #expect(after >= platterAfter - 1, "the platter (\(platterAfter)) must fit the window (\(after))")
        delegate.setAmbienceVisible(false)
        await settle(40)
        print("AXD closed again: window \(delegate.panelFrame.height), platter \(delegate.navigation.platterHeight)")
        #expect(delegate.panelFrame.height >= delegate.navigation.platterHeight - 1)
    }
}
