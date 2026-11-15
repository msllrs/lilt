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
        try await withPreservedPanel(delegate) { await drawerGrows(delegate) }
    }

    private func drawerGrows(_ delegate: AppDelegate) async {
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

    /// Puts the app's own player on a song with two more queued by hand, so Up Next has rows and
    /// stays open (an empty list folds itself away after 1.5s, mid-test). The app's saved
    /// playback is put back afterwards, in the defaults and in the player.
    private func withQueuedSongs(_ player: PlayerService, _ body: () async throws -> Void) async throws {
        let key = "playbackState"
        let saved = UserDefaults.standard.data(forKey: key)
        defer {
            if let saved {
                UserDefaults.standard.set(saved, forKey: key)
                player.restore()
            } else {
                player.stop()
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        let songs = ["now", "queued1", "queued2"].map { Track(id: $0, title: $0, artist: "Tool") }
        let state: [String: Any] = ["queue": try JSONSerialization.jsonObject(with: JSONEncoder().encode(songs)), "index": 0, "time": 0, "manualCount": 2]
        UserDefaults.standard.set(try JSONSerialization.data(withJSONObject: state), forKey: key)
        player.restore()
        try await body()
    }

    @Test func miniWindowGrowsForTheDrawerWithTheQueueOpen() async throws {
        let delegate = try #require(AppDelegate.shared)
        try await withPreservedPanel(delegate) {
            try await withQueuedSongs(delegate.player) { try await drawerGrowsWithQueueOpen(delegate) }
        }
    }

    private func drawerGrowsWithQueueOpen(_ delegate: AppDelegate) async throws {
        try #require(delegate.player.upcoming.count == 2, "the seeded queue should show in Up Next")
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
