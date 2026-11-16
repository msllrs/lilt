import Foundation
import Testing
@testable import Lilt

/// A row warms its page (fetches it ahead, so it opens at once) only once the pointer rests on
/// it. Warming on every hover fetched and parsed one artist page after another as a library
/// shelf scrolled under a resting pointer: 21% of the main thread in a 15-second sample.
@MainActor
struct HoverWarmerTests {
    /// Rows sliding past the pointer, as they do under a resting pointer in a scroll, warm
    /// nothing; a pointer that settles on a row still warms that row's page before it's clicked.
    /// (A hosted row doesn't get hover from synthetic events, so this drives the row's warmer,
    /// which its `onHover` feeds, directly.)
    @Test func onlyARowThePointerRestsOnWarmsItsPage() async throws {
        var warmed: [Int] = []
        let warmers = (0..<12).map { row in HoverWarmer { warmed.append(row) } }
        // Down the rows a frame or two each, as a scroll carries them past.
        for warmer in warmers {
            warmer.hovering(true)
            try await Task.sleep(for: .milliseconds(30))
            if warmer !== warmers.last { warmer.hovering(false) }
        }
        // Then settle on the last.
        try await Task.sleep(for: HoverWarmer.dwell * 3)
        #expect(warmed == [11], "rows passed under the pointer warmed \(warmed)")
        #expect(HoverWarmer.dwell <= .milliseconds(300), "a pointer heading for a row to click it still finds the page warm")
    }

}
