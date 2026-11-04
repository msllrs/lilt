import AppKit
import Testing
@testable import Lilt

/// The Dock tile only needs to spin while the Dock can be seen: always, when it's kept shown;
/// only while the pointer has brought it up, when it hides itself. The app switcher (⌘-Tab)
/// shows the tile too, whether or not the Dock is up.
struct DockVisibilityTests {
    private let screen = NSRect(x: 0, y: 0, width: 2560, height: 1440)

    @Test func aDockKeptShownTakesRoomFromTheScreen() {
        // Only the menu bar's 30pt at the top: the Dock hides itself.
        #expect(!DockVisibility.isKeptShown(frame: screen, visibleFrame: NSRect(x: 0, y: 0, width: 2560, height: 1410)))
        // Shown along the bottom, the left or the right.
        #expect(DockVisibility.isKeptShown(frame: screen, visibleFrame: NSRect(x: 0, y: 80, width: 2560, height: 1330)))
        #expect(DockVisibility.isKeptShown(frame: screen, visibleFrame: NSRect(x: 80, y: 0, width: 2480, height: 1410)))
        #expect(DockVisibility.isKeptShown(frame: screen, visibleFrame: NSRect(x: 0, y: 0, width: 2480, height: 1410)))
    }

    @Test func thePointerAtAnEdgeBringsTheDockUp() {
        #expect(DockVisibility.bringsDockUp(pointer: CGPoint(x: 1280, y: 0), in: screen, wasUp: false))
        #expect(DockVisibility.bringsDockUp(pointer: CGPoint(x: 0, y: 700), in: screen, wasUp: false))
        #expect(DockVisibility.bringsDockUp(pointer: CGPoint(x: 2559, y: 700), in: screen, wasUp: false))
        #expect(!DockVisibility.bringsDockUp(pointer: CGPoint(x: 1280, y: 700), in: screen, wasUp: false))
        // Near the edge but not at it: the Dock hasn't come up yet.
        #expect(!DockVisibility.bringsDockUp(pointer: CGPoint(x: 1280, y: 60), in: screen, wasUp: false))
    }

    @Test func theDockStaysUpWhileThePointerIsOverIt() {
        #expect(DockVisibility.bringsDockUp(pointer: CGPoint(x: 1280, y: 60), in: screen, wasUp: true))
        #expect(!DockVisibility.bringsDockUp(pointer: CGPoint(x: 1280, y: 700), in: screen, wasUp: true))
    }

    /// ⌘-Tab's switcher draws every app's tile, ours spinning one included, while the Dock stays
    /// hidden. macOS doesn't say when the switcher is up, but it's only up while ⌘ is held.
    @Test func theAppSwitcherShowsTheTileWithTheDockHidden() {
        #expect(DockVisibility.isInSight(dockUp: false, modifiers: [.command]))
        #expect(DockVisibility.isInSight(dockUp: false, modifiers: [.command, .shift]), "⌘⇧-Tab goes backwards through the same switcher")
        #expect(!DockVisibility.isInSight(dockUp: false, modifiers: []))
        #expect(!DockVisibility.isInSight(dockUp: false, modifiers: [.option, .shift]))
        #expect(DockVisibility.isInSight(dockUp: true, modifiers: []))
    }
}
