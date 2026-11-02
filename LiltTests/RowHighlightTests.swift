import Testing
@testable import Lilt

/// A row's hover and playing highlight is concentric with its cover: the same gap on every side,
/// so its rounded corners follow the cover's. The cover itself stays where it was.
struct RowHighlightTests {
    @Test func theHighlightSitsAsFarFromTheCoverOnTheSideAsAboveAndBelow() {
        #expect(TrackRow.horizontalPadding == TrackRow.verticalPadding)
        #expect(BrowseRow.horizontalPadding == BrowseRow.verticalPadding)
    }

    @Test func theCoverKeepsItsPlaceFromThePanelEdge() {
        // 8pt list inset plus 8pt row padding, before this change.
        #expect(Theme.Space.rowInset + TrackRow.horizontalPadding == 16)
        #expect(Theme.Space.rowInset + BrowseRow.horizontalPadding == 16)
    }

    @Test func rowsKeepTheirHeight() {
        let height = Theme.Size.rowArtwork + 2 * TrackRow.verticalPadding
        #expect(height == 52)
        #expect(Theme.Size.row == 52)
    }
}
