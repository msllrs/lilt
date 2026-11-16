import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Lilt

/// What made a library shelf's page lag to open and stutter to scroll, from a 15-second sample
/// of the running app opening Artists and scrolling it (the main thread was idle 13% of it):
/// - the cover cache, full, sorted every cover it held to make room for each one coming in, as
///   the shelf brought in every cover of the library (19% of the main thread);
/// - rows warmed their page as the pointer passed over them, so a scroll under a resting
///   pointer fetched and parsed one artist page after another, the parse on the main thread
///   (21%);
/// - the now-playing bar redrew on every frame of a scroll, reading how much list was left
///   below, where it only fades its glass over the first 24 points.
@MainActor
struct ShelfScrollPerformanceTests {
    // MARK: The cover cache

    private static func cover(_ side: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: side, height: side))
        image.lockFocus()
        NSColor(red: 0.6, green: 0.2, blue: 0.3, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: side, height: side).fill()
        image.unlockFocus()
        return image
    }

    /// Making room in a full cache costs about what storing a cover does anyway, rather than a
    /// sort of everything in it: covers stored into a full cache take no longer than the same
    /// covers stored again over themselves, which never needs room.
    @Test func aFullCacheMakesRoomWithoutSortingItForEveryCover() async {
        let cache = ImageCache.shared
        let image = Self.cover(288)
        let run = UUID().uuidString
        // Past the 160 MB limit at 288 × 288 (about 500 covers), so the cache is full.
        let filling = (0..<700).map { URL(string: "https://lh3.googleusercontent.com/test-\(run)-fill-\($0)")! }
        for url in filling { cache.store(image, for: url) }

        let incoming = (0..<300).map { URL(string: "https://lh3.googleusercontent.com/test-\(run)-new-\($0)")! }
        let clock = ContinuousClock()
        let intoFull = clock.measure { for url in incoming { cache.store(image, for: url) } }
        // The same covers again, each over its own entry: the same work, no room to make.
        let over = clock.measure { for url in incoming { cache.store(image, for: url) } }

        let ratio = Double(intoFull.components.attoseconds / 1_000_000_000 + intoFull.components.seconds * 1_000_000_000)
            / Double(max(over.components.attoseconds / 1_000_000_000 + over.components.seconds * 1_000_000_000, 1))
        #expect(ratio < 2, "300 covers into a full cache took \(intoFull), the same 300 over themselves \(over): \(String(format: "%.1f", ratio))×")
    }

    // MARK: Parsing a page

    /// A playlist page's response the size of Liked Music's first (100 rows, deep renderers).
    private static func bigPage() -> JSONObject {
        func row(_ i: Int) -> [String: Any] {
            var deep: Any = ["text": "padding \(i)"]
            for level in 0..<24 { deep = ["level\(level)": deep, "sibling\(level)": ["a": [1, 2, 3], "b": "x"]] }
            return ["musicResponsiveListItemRenderer": [
                "playlistItemData": ["videoId": "v\(i)"],
                "flexColumns": [["musicResponsiveListItemFlexColumnRenderer": ["text": ["runs": [["text": "Song \(i)"]]]]]],
                "menu": deep,
                "overlay": deep,
                "thumbnail": deep,
            ]]
        }
        return JSONObject(value: ["contents": ["twoColumnBrowseResultsRenderer": ["secondaryContents": ["sectionListRenderer": ["contents": [[
            "musicPlaylistShelfRenderer": ["playlistId": "LM", "contents": (0..<400).map(row)],
        ]]]]]]])
    }

    /// The main thread keeps drawing while a big page is read: the reading happens off it.
    @Test func aBigPageIsReadOffTheMainThread() async throws {
        let page = Self.bigPage()
        let auth = AuthService()
        let music = YTMusicClient(auth: auth, fetchPage: { _ in page }, persists: false, fetchAccount: { nil })
        let item = BrowseItem(id: "VLtest-big", kind: .playlist, title: "Big", subtitle: "Playlist")

        // A main-actor tick every few milliseconds, noting the longest wait between two.
        var longest: Duration = .zero
        var ticking = true
        let clock = ContinuousClock()
        let ticker = Task { @MainActor in
            var last = clock.now
            while ticking {
                try? await Task.sleep(for: .milliseconds(2))
                let now = clock.now
                longest = max(longest, now - last)
                last = now
            }
        }
        let started = clock.now
        _ = try await music.page(for: item)
        let took = clock.now - started
        ticking = false
        await ticker.value
        #expect(longest < .milliseconds(50), "reading the page took \(took) and held the main thread for \(longest) at a stretch")
    }

    // MARK: The now-playing bar during a scroll

    /// The bar fades its glass over the first 24 points of list below it; past that, a scroll
    /// changes nothing it draws, so it isn't told.
    @Test func scrollingFarFromTheEndDoesNotRedrawTheBar() {
        let tracker = ScrollTracker()
        tracker.activeKey = "library/artists"
        tracker.report(remainingBelow: 4_000, for: "library/artists")
        final class Count: @unchecked Sendable { var value = 0 }
        let count = Count()
        var changed: Int { count.value }
        func watch() {
            withObservationTracking { _ = tracker.activeRemainingBelow } onChange: { count.value += 1 }
        }
        watch()
        for remaining in stride(from: 3_990, through: 100, by: -10) {
            tracker.report(remainingBelow: CGFloat(remaining), for: "library/artists")
            if changed > 0 { break }
        }
        #expect(changed == 0, "a scroll far from the end told the bar something changed")

        // Near the end it fades, so it is told then.
        count.value = 0
        watch()
        tracker.report(remainingBelow: 12, for: "library/artists")
        #expect(changed > 0, "the last 24 points still fade the bar's glass")
        #expect(tracker.activeRemainingBelow == 12)
    }
}
