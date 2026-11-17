import AppKit
import SwiftUI
import Testing
@testable import Lilt

/// What a library shelf's first scroll costs. A 30-second sample of the running app, opening
/// Artists and scrolling it for the first time, had the main thread 68% busy, nearly all of it
/// SwiftUI building each row as it came into the lazy stack; over rows already built, the same
/// scroll left it 46% idle. So the cost is what each row builds, and a row at rest built every
/// part a hovered, playing or shining row shows: a marquee for its title and byline, the cover's
/// play button, the record's hub, the sweep of light, the reader that follows the cover for the
/// hero morph. Counted by the DEBUG-only tally of those parts as a shelf of rows is scrolled
/// through for the first time, under no pointer, with nothing playing from it. A playlist's
/// songs are scrolled the same way: each song row held an add-to-queue button, hidden.
@MainActor
struct ShelfFirstScrollTests {
    private static let width: CGFloat = 320
    private static let height: CGFloat = 640
    private static let count = 300

    /// A shelf's worth of artists, albums with their artist linked, and playlists whose titles
    /// run past the row.
    private static func items(_ run: String) -> [BrowseItem] {
        (0..<count).map { i in
            switch i % 3 {
            case 0:
                return BrowseItem(id: "UC-first-scroll-\(run)-\(i)", kind: .artist, title: "Artist \(i)", subtitle: "Artist")
            case 1:
                var item = BrowseItem(id: "MPREb-first-scroll-\(run)-\(i)", kind: .album, title: "Album \(i)", subtitle: "Album • Tool • 2001")
                item.artist = "Tool"
                item.artistId = "UC-tool"
                return item
            default:
                return BrowseItem(id: "VL-first-scroll-\(run)-\(i)", kind: .playlist, title: "A playlist whose title runs well past the end of the row \(i)", subtitle: "Playlist • Someone with a long name • 120 songs")
            }
        }
    }

    private func findScrollView(in view: NSView?) -> NSScrollView? {
        guard let view else { return nil }
        if let scroll = view as? NSScrollView { return scroll }
        for sub in view.subviews { if let found = findScrollView(in: sub) { return found } }
        return nil
    }

    private struct Scrolled {
        var rows = 0
        var parts: [String: Int] = [:]
        var milliseconds = 0.0
    }

    /// A long playlist's songs, as its page lists them: some without a length, as YouTube Music
    /// leaves some, and some explicit.
    private static func songs(_ run: String) -> [Track] {
        (0..<count).map { i in
            Track(
                id: "song-first-scroll-\(run)-\(i)", title: "A song whose title runs well past the end of the row \(i)",
                artist: "Someone with a long name", durationText: i % 4 == 0 ? nil : "3:\(10 + i % 50)",
                isExplicit: i % 5 == 0
            )
        }
    }

    /// Hosts a shelf page's list of `items`, as `LibraryShelfScreen` lays it out, and scrolls
    /// through it.
    private func scrollThrough(_ items: [BrowseItem]) throws -> Scrolled {
        for item in items { RowBuildCounts.items[item.id] = nil }
        defer { for item in items { RowBuildCounts.items[item.id] = nil } }
        return try scrollThrough(ForEach(items) { BrowseRow(item: $0) }) {
            items.filter { (RowBuildCounts.items[$0.id] ?? 0) > 0 }.count
        }
    }

    /// Hosts a playlist page's songs, as its page lists them, and scrolls through them.
    private func scrollThrough(_ songs: [Track]) throws -> Scrolled {
        for song in songs { RowBuildCounts.rows[song.id] = nil; RowBuildCounts.slots[song.id] = nil }
        defer { for song in songs { RowBuildCounts.rows[song.id] = nil; RowBuildCounts.slots[song.id] = nil } }
        let playlist = BrowseItem(id: "VL-first-scroll-songs", kind: .playlist, title: "Playlist", subtitle: "Playlist • Someone • 300 songs")
        return try scrollThrough(TrackRows(tracks: songs, source: playlist)) {
            songs.filter { (RowBuildCounts.rows[$0.id] ?? 0) > 0 }.count
        }
    }

    /// Hosts `rows` in a page's lazy list and scrolls through it top to bottom a step at a time,
    /// laying out and drawing each step, all on the main thread without a break, so no other
    /// test's rows are tallied with these. `built` counts the rows that came in.
    private func scrollThrough(_ rows: some View, built: () -> Int) throws -> Scrolled {
        let keys = ["playbackState", PlayerService.playheadKey, PlayerService.gaplessKey, PlayerService.legacyGaplessModeKey, "navigationState"]
        let saved = keys.map { UserDefaults.standard.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, saved) {
                if let value { UserDefaults.standard.set(value, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
            }
        }
        let auth = AuthService()
        let root = AnyView(
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    rows
                }
                .padding(.horizontal, Theme.Space.rowInset)
                .padding(.bottom, Theme.Space.sm)
            }
            .scrollIndicators(.never)
            .environment(\.heroTracking, true)
            .environment(\.colorScheme, .light)
            .environment(auth)
            .environment(PlayerService(auth: auth, makeBridge: { FakeBridge() }))
            .environment(YTMusicClient(auth: auth, persists: false))
            .environment(NavigationModel())
            .frame(width: Self.width, height: Self.height)
        )
        RowBuildCounts.parts = [:]
        RowBuildCounts.countsParts = true
        defer {
            RowBuildCounts.countsParts = false
            RowBuildCounts.parts = [:]
        }

        let clock = ContinuousClock()
        let started = clock.now
        let hosting = NSHostingView(rootView: root)
        hosting.frame = CGRect(x: 0, y: 0, width: Self.width, height: Self.height)
        let window = NSWindow(contentRect: CGRect(x: -10_000, y: -10_000, width: Self.width, height: Self.height), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        defer { window.close() }
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        let scrollView = try #require(findScrollView(in: hosting), "the shelf's list is an NSScrollView")
        let clip = scrollView.contentView
        // Half a cover a step, as a brisk scroll carries the list.
        let step = Theme.Size.rowArtwork / 2
        var y: CGFloat = 0
        while y < (scrollView.documentView?.frame.height ?? 0) - Self.height {
            y += step
            clip.scroll(to: NSPoint(x: 0, y: y))
            scrollView.reflectScrolledClipView(clip)
            hosting.layoutSubtreeIfNeeded()
            hosting.displayIfNeeded()
        }
        let took = clock.now - started
        return Scrolled(
            rows: built(),
            parts: RowBuildCounts.parts,
            milliseconds: Double(took.components.seconds) * 1_000 + Double(took.components.attoseconds) / 1e15
        )
    }

    /// Rows at rest build none of what only a hovered, playing or shining row shows: as the
    /// pointer arrives, the row builds its marquees, its cover's play button and the reader for
    /// the hero morph; a shine builds its sweep; the playing album's row builds its record.
    @Test func restingRowsBuildNoneOfTheirHoverOnlyParts() throws {
        // Once for the types' first use, so the timing below is the rows' own.
        _ = try scrollThrough(Self.items("warm"))
        let scrolled = try scrollThrough(Self.items("measured"))
        let total = scrolled.parts.values.reduce(0, +)
        let parts = scrolled.parts.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
        print(String(format: "ShelfFirstScroll: %d rows came in, %d hover-only parts built (%@), %.0f ms to scroll through", scrolled.rows, total, parts, scrolled.milliseconds))
        #expect(scrolled.rows == Self.count, "the scroll brought every row in (\(scrolled.rows) of \(Self.count))")
        #expect(total == 0, "\(scrolled.rows) resting rows built \(total) parts that only a hovered, playing or shining row shows: \(parts)")
    }

    /// A playlist's songs at rest build no add-to-queue buttons: the hovered row builds its own.
    @Test func restingSongRowsBuildNoQueueButtons() throws {
        _ = try scrollThrough(Self.songs("warm"))
        let scrolled = try scrollThrough(Self.songs("measured"))
        let total = scrolled.parts.values.reduce(0, +)
        let parts = scrolled.parts.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
        print(String(format: "SongFirstScroll: %d rows came in, %d hover-only parts built (%@), %.0f ms to scroll through", scrolled.rows, total, parts, scrolled.milliseconds))
        #expect(scrolled.rows == Self.count, "the scroll brought every song in (\(scrolled.rows) of \(Self.count))")
        #expect(total == 0, "\(scrolled.rows) resting song rows built \(total) parts that only a hovered, playing or shining row shows: \(parts)")
    }
}
