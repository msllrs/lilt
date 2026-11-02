import AppKit
import Testing
@testable import Lilt

/// Which song changes post a notification: only a click or key press in the panel, while it's
/// in front, counts as the listener's own (and doesn't post).
@MainActor
struct SongNotifierTests {
    private let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.borderless], backing: .buffered, defer: false)
    private let other = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.borderless], backing: .buffered, defer: false)

    private func click(in window: NSWindow, at time: TimeInterval) -> NSEvent {
        NSEvent.mouseEvent(
            with: .leftMouseUp, location: .zero, modifierFlags: [], timestamp: time,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0
        )!
    }

    @Test func aClickInThePanelInFrontIsTheListenersOwn() {
        #expect(SongNotifier.isOwnAction(click(in: panel, at: 100), in: panel, panelInFront: true, now: 100.05))
    }

    @Test func everythingElsePosts() {
        // A song ending, a media key: nothing in the panel caused it.
        #expect(!SongNotifier.isOwnAction(nil, in: panel, panelInFront: true, now: 100))
        // The panel hidden or not key: the listener isn't looking at it.
        #expect(!SongNotifier.isOwnAction(click(in: panel, at: 100), in: panel, panelInFront: false, now: 100.05))
        // A click somewhere else (the Dock menu, another window).
        #expect(!SongNotifier.isOwnAction(click(in: other, at: 100), in: panel, panelInFront: true, now: 100.05))
        // The last click, lingering as the current event long after it was handled.
        #expect(!SongNotifier.isOwnAction(click(in: panel, at: 100), in: panel, panelInFront: true, now: 280))
    }
}
