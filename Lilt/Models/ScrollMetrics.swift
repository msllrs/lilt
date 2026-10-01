import CoreGraphics

/// What the screens need from a scroll view's geometry: the normalised offset, and enough to
/// know how much content extends past the visible area.
struct ScrollMetrics: Equatable {
    var offset: CGFloat
    var contentHeight: CGFloat
    var visibleHeight: CGFloat

    /// Content extending below the visible area (what sits under the now-playing bar).
    var remainingBelow: CGFloat { contentHeight - visibleHeight - offset }
}
