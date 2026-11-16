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
/// over the first points, and how much list is left under the now-playing bar, near the end.
/// Both are kept only as far as they change anything, so between the two a scroll leaves this
/// as it was and `onScrollGeometryChange` has nothing to tell the screen. Kept as the raw
/// offset, it changed the screen's state on every frame and re-laid out its header with it.
struct ListScroll: Equatable {
    var backdropVisibility: CGFloat = 0
    /// Up to `ScrollTracker.glassFadeDistance`, as the now-playing bar is told it.
    var remainingBelow: CGFloat = 0

    init() {}

    init(_ metrics: ScrollMetrics) {
        backdropVisibility = HeaderBackdrop.visibility(forScrollOffset: metrics.offset)
        remainingBelow = ScrollTracker.counted(metrics.remainingBelow)
    }
}
