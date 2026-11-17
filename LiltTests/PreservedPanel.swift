import AppKit
@testable import Lilt

/// The test host's panel goes to one test at a time. Swift Testing runs a suite's tests at once,
/// interleaved at every await on the main actor, so a second test could begin while the first
/// had collapsed to the mini player, take mini for the panel as it was, and put it back last:
/// the panel stayed mini and its saved frame the platter's height.
@MainActor
private enum PanelTurns {
    /// Ends when the last test to ask for the panel is done with it.
    static var last: Task<Void, Never>?
}

/// Runs `body` on the test host's own panel and leaves it, and the defaults the real app reads
/// at launch, as they were. The panel's changes are deferred and animated, and each one saves
/// the navigation state, the window frame and the expanded height as it lands, so the panel is
/// put back first, given time to settle, and the saved values are written over its last saves.
/// Waits for any other test using the panel to finish first.
@MainActor
func withPreservedPanel(_ delegate: AppDelegate, _ body: () async throws -> Void) async throws {
    let (done, finish) = AsyncStream<Void>.makeStream()
    let previous = PanelTurns.last
    PanelTurns.last = Task { for await _ in done {} }
    defer { finish.finish() }
    await previous?.value

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
    // A frame still on its way would save itself again as it lands.
    for _ in 0..<50 where navigation.isFrameAnimating { try? await Task.sleep(for: .milliseconds(20)) }
    for (key, value) in zip(keys, saved) {
        if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
    }
    if let failure { throw failure }
}
