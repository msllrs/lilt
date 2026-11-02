import CoreGraphics
import Testing
@testable import Lilt

/// An Up Next row's hover highlight is concentric with its 28pt cover: it reaches as far past
/// the cover at the sides as above and below. The covers themselves stay lined up with the
/// platter's artwork (`QueueShadowTests` finds the first cover at the list's leading edge).
@MainActor
struct QueueRowHighlightTests {
    @Test func theHighlightSitsAsFarFromTheCoverOnTheSideAsAboveAndBelow() {
        #expect(QueueList.rowPadding == QueueList.rowGutter)
        #expect(QueueList.rowPadding > 0)
    }

    @Test func itsCornersFollowTheCover() {
        let concentric: CGFloat = Theme.Radius.artwork(28) + QueueList.rowGutter
        #expect(QueueList.rowHighlightRadius == concentric)
    }

    @Test func itsGapMatchesTheMainListsRows() {
        #expect(QueueList.rowPadding == Theme.Space.rowPadding)
        #expect(QueueList.rowHeight == 40)
    }
}
