import AppKit
@testable import Lilt

/// Runs `body` on the test host's own panel and leaves it, and the defaults the real app reads
/// at launch, as they were. The panel's changes are deferred and animated, and each one saves
/// the navigation state, the window frame and the expanded height as it lands, so the panel is
/// put back first, given time to settle, and the saved values are written over its last saves.
@MainActor
func withPreservedPanel(_ delegate: AppDelegate, _ body: () async throws -> Void) async throws {
    let defaults = UserDefaults.standard
    let keys = ["navigationState", "NSWindow Frame \(PanelWindow.autosaveName)", "expandedPanelHeight"]
    let saved = keys.map { defaults.object(forKey: $0) }
    let navigation = delegate.navigation
    let (wasMini, hadDrawer, hadQueue) = (navigation.isMiniPlayer, navigation.isAmbienceVisible, navigation.isQueueVisible)
    var failure: Error?
    do { try await body() } catch { failure = error }
    delegate.setAmbienceVisible(hadDrawer)
    delegate.setQueueVisible(hadQueue)
    delegate.setMiniPlayer(wasMini)
    for _ in 0..<40 { try? await Task.sleep(for: .milliseconds(20)) }
    for (key, value) in zip(keys, saved) {
        if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
    }
    if let failure { throw failure }
}
