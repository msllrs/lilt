import Foundation
import Observation

/// How much list content currently sits beneath the now-playing bar, per screen. The bar reads
/// the value for whichever screen is on top and shows its glass only when something is under it.
@MainActor
@Observable
final class ScrollTracker {
    static let searchKey = "search"

    /// Points of content extending below the visible area, keyed by screen.
    private var remainingBelow: [String: CGFloat] = [:]
    /// The screen currently on top of the navigation column.
    var activeKey: String = ScrollTracker.searchKey

    var activeRemainingBelow: CGFloat { remainingBelow[activeKey] ?? 0 }

    func report(remainingBelow value: CGFloat, for key: String) {
        let clamped = max(value, 0)
        if remainingBelow[key] != clamped { remainingBelow[key] = clamped }
    }
}
