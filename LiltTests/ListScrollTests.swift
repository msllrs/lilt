import CoreGraphics
import Testing
@testable import Lilt

/// What a list screen keeps of its scroll. A library shelf kept its raw offset in view state on
/// every frame of a scroll, so the screen re-laid out its header each frame, where the header's
/// backdrop is fully in after the first 24 points and nothing about it changes after that.
struct ListScrollTests {
    /// Artists in full: about 470 rows in a panel-tall view.
    private static func metrics(offset: CGFloat) -> ScrollMetrics {
        ScrollMetrics(offset: offset, contentHeight: 26_000, visibleHeight: 600)
    }

    /// Past the backdrop's fade and short of the list's end, a scroll changes nothing a screen
    /// keeps, so `onScrollGeometryChange` has nothing to tell it.
    @Test func aScrollPastTheHeaderFadeAndFarFromTheEndChangesNothing() {
        let settled = ListScroll(Self.metrics(offset: HeaderBackdrop.fadeDistance))
        for offset in stride(from: HeaderBackdrop.fadeDistance, through: 20_000, by: 7) {
            #expect(ListScroll(Self.metrics(offset: offset)) == settled, "a scroll to \(offset) changed the screen's scroll state")
            if ListScroll(Self.metrics(offset: offset)) != settled { break }
        }
        #expect(settled.backdropVisibility == 1)
    }

    /// The backdrop still fades in over the first points, and the bar is still told about the
    /// last of the list.
    @Test func theHeaderFadeAndTheListsEndStillChangeIt() {
        #expect(ListScroll(Self.metrics(offset: 0)).backdropVisibility == 0)
        #expect(ListScroll(Self.metrics(offset: HeaderBackdrop.fadeDistance / 2)).backdropVisibility == 0.5)
        let end = 26_000 - 600 as CGFloat
        #expect(ListScroll(Self.metrics(offset: end - 12)).remainingBelow == 12)
        #expect(ListScroll(Self.metrics(offset: end)).remainingBelow == 0)
    }
}
