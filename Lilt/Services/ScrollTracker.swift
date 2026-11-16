import Foundation
import Observation

/// How much list content currently sits beneath the now-playing bar, per screen. The bar reads
/// the value for whichever screen is on top and shows its glass only when something is under it.
@MainActor
@Observable
final class ScrollTracker {
    static let searchKey = "search"

    /// How much content below the bar fades its glass fully in. The bar draws nothing different
    /// past it, so that's as far as this counts.
    nonisolated static let glassFadeDistance: CGFloat = 24

    /// Points of content extending below the visible area, keyed by screen, up to
    /// `glassFadeDistance`: a scroll far from a list's end then changes nothing here, where a
    /// value changing on every frame redrew the bar on every frame.
    private var remainingBelow: [String: CGFloat] = [:]
    /// The screen currently on top of the navigation column.
    var activeKey: String = ScrollTracker.searchKey

    var activeRemainingBelow: CGFloat { remainingBelow[activeKey] ?? 0 }

    func report(remainingBelow value: CGFloat, for key: String) {
        let clamped = Self.counted(value)
        if remainingBelow[key] != clamped { remainingBelow[key] = clamped }
    }

    /// Content below the bar as far as it is counted: none to `glassFadeDistance`.
    nonisolated static func counted(_ remainingBelow: CGFloat) -> CGFloat {
        min(max(remainingBelow, 0), glassFadeDistance)
    }
}
