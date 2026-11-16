import CoreGraphics
import SwiftUI

/// What the screens need from a scroll view's geometry: the normalised offset, and enough to
/// know how much content extends past the visible area.
struct ScrollMetrics: Equatable {
    var offset: CGFloat
    var contentHeight: CGFloat
    var visibleHeight: CGFloat

    /// Content extending below the visible area (what sits under the now-playing bar).
    var remainingBelow: CGFloat { contentHeight - visibleHeight - offset }
}

/// What a list screen under a header acts on from its scroll: the header's backdrop, faded in
/// over the first points, and how much list is left under the now-playing bar.
struct ListScroll: Equatable {
    var offset: CGFloat = 0
    var remainingBelow: CGFloat = 0

    init() {}

    init(_ metrics: ScrollMetrics) {
        offset = metrics.offset
        remainingBelow = metrics.remainingBelow
    }

    var backdropVisibility: CGFloat { HeaderBackdrop.visibility(forScrollOffset: offset) }
}
