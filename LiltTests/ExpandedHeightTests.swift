import Testing
@testable import Lilt

/// The height the panel comes back to from the mini player is the one it had when it went mini.
/// Launched in mini, the window starts at the panel's minimum (the saved mini frame clamped up
/// to it) and that's no height of yours: remembering it brought a 949pt panel back at 480 after
/// a relaunch, as every test run (whose host launches in mini) also left it.
@MainActor
struct ExpandedHeightTests {
    @Test func aSettledPanelGoingMiniIsRemembered() {
        #expect(AppDelegate.remembersExpandedHeight(collapsingFrom: 949, launching: false, animating: false))
    }

    @Test func aFrameCaughtMidMoveIsNot() {
        #expect(!AppDelegate.remembersExpandedHeight(collapsingFrom: 700, launching: false, animating: true))
    }

    @Test func launchingInMiniIsNot() {
        #expect(!AppDelegate.remembersExpandedHeight(collapsingFrom: Theme.Size.panelMinHeight, launching: true, animating: false))
        #expect(!AppDelegate.remembersExpandedHeight(collapsingFrom: 949, launching: true, animating: false))
    }
}
