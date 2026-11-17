import AppKit
import SwiftUI
import Testing
@testable import Lilt

/// A change rebuilds only the parts of an album page, and the album rows, that it touches. A
/// song change or a pause redraws the playing album's row and the compact header's disc, not
/// every album row on screen or the page around them; the pointer coming into the header starts
/// its title's marquee without rebuilding the page and its 24 song rows. Counted by the
/// DEBUG-only tallies of row and page builds; every one rebuilt for nothing is main-thread work,
/// felt as a hitch in whatever else is moving.
@MainActor
struct BrowseInvalidationTests {
    private static let width: CGFloat = 320

    /// The album the page shows, and the albums the rows show; the queue is started from the
    /// first of these (or from `source`).
    private static let pageId = "MPREb-page-invalidation"
    private static func albums(count: Int = 10) -> [BrowseItem] {
        (0..<count).map { BrowseItem(id: "MPREb-row-invalidation-\($0)", kind: .album, title: "Album \($0)", subtitle: "Album • Tool", artworkURL: nil) }
    }

    /// A player on `queue[0]`, started from the album or playlist `source`, on fake web players;
    /// seeded through the saved state it resumes from, with the real app's put back after.
    private func withPlayer(_ queue: [Track], source: String, _ body: (PlayerService, FakePlayers) async throws -> Void) async throws {
        let keys = ["playbackState", PlayerService.playheadKey, PlayerService.gaplessKey, PlayerService.legacyGaplessModeKey, "navigationState"]
        let saved = keys.map { UserDefaults.standard.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, saved) {
                if let value { UserDefaults.standard.set(value, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
            }
        }
        let state: [String: Any] = ["queue": try JSONSerialization.jsonObject(with: JSONEncoder().encode(queue)), "index": 0, "time": 0, "sourceId": source, "sourceTitle": "Source"]
        UserDefaults.standard.set(try JSONSerialization.data(withJSONObject: state), forKey: "playbackState")
        UserDefaults.standard.set(false, forKey: PlayerService.gaplessKey)
        let fakes = FakePlayers()
        let player = PlayerService(auth: AuthService(), makeBridge: {
            let fake = FakeBridge()
            fakes.all.append(fake)
            return fake
        })
        try await body(player, fakes)
    }

    private struct Hosted {
        let window: NSWindow
        let hosting: NSHostingView<AnyView>
    }

    private func host(_ view: some View, player: PlayerService, music: YTMusicClient, navigation: NavigationModel = NavigationModel(), height: CGFloat) -> Hosted {
        let root = AnyView(view
            .environment(\.colorScheme, .light)
            .environment(player)
            .environment(music)
            .environment(navigation)
            .environment(AuthService())
            .environment(ScrollTracker())
            .environment(CollapsedSections())
            .frame(width: Self.width, height: height, alignment: .top))
        let hosting = NSHostingView(rootView: root)
        hosting.frame = CGRect(x: 0, y: 0, width: Self.width, height: height)
        let window = NSWindow(contentRect: CGRect(x: -10_000, y: -10_000, width: Self.width, height: height), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderFrontRegardless()
        return Hosted(window: window, hosting: hosting)
    }

    private func settle(_ hosted: Hosted, _ steps: Int = 10) async {
        for _ in 0..<steps {
            try? await Task.sleep(for: .milliseconds(20))
            hosted.hosting.layoutSubtreeIfNeeded()
        }
    }

    // MARK: Album rows

    private func itemsBuilt(_ items: [BrowseItem]) -> Int { items.reduce(0) { $0 + (RowBuildCounts.items[$1.id] ?? 0) } }
    private func forget(_ items: [BrowseItem]) { for item in items { RowBuildCounts.items[item.id] = nil } }

    /// Ten album rows, the queue playing from the first; `change` is made and the rows it
    /// rebuilt are returned.
    private func albumRowsRebuilt(by change: (PlayerService) -> Void) async throws -> Int {
        let albums = Self.albums()
        let songs = (0..<3).map { Track(id: "row-invalidation-song-\($0)", title: "Song \($0)", artist: "Tool") }
        var rebuilt = 0
        try await withPlayer(songs, source: albums[0].id) { player, fakes in
            let music = YTMusicClient(auth: AuthService(), persists: false)
            let hosted = host(VStack(spacing: 0) { ForEach(albums) { BrowseRow(item: $0) } }, player: player, music: music, height: 600)
            defer { hosted.window.close() }
            fakes.startPlaying(player)
            await settle(hosted)
            #expect(player.sourceId == albums[0].id && player.isPlaying, "the queue plays from the first album")
            #expect(itemsBuilt(albums) >= albums.count, "every row was built to start with")
            forget(albums)
            change(player)
            await settle(hosted)
            rebuilt = itemsBuilt(albums)
            forget(albums)
        }
        return rebuilt
    }

    @Test func pausingRebuildsOnlyThePlayingAlbumsRow() async throws {
        let rebuilt = try await albumRowsRebuilt { player in
            player.togglePlayPause()
            #expect(!player.isPlaying)
        }
        #expect(rebuilt <= 1, "the playing album's row redraws its disc at most; the other nine needn't (\(rebuilt) rebuilt)")
    }

    @Test func aSongChangeRebuildsNoAlbumRows() async throws {
        let rebuilt = try await albumRowsRebuilt { player in
            let before = player.current?.id
            player.next()
            #expect(player.current?.id != before, "the next song is on")
        }
        #expect(rebuilt <= 1, "the album playing is the same and so is every row (\(rebuilt) rebuilt)")
    }

    // MARK: The page

    private func pagesBuilt() -> Int { PageBuildCounts.pages[Self.pageId] ?? 0 }

    /// The album page, its queue playing from the page; `change` is made with the page hosted,
    /// and the page builds and song rows it caused are returned.
    private func pageRebuilt(by change: (PlayerService, Hosted) async -> Void) async throws -> (pages: Int, rows: Int) {
        let response = AlbumScrollTests.albumResponse(tracks: 24)
        let songs = (0..<24).map { Track(id: "album-scroll-\($0)", title: "Track \($0 + 1)", artist: "Ludwig Göransson") }
        var result = (pages: 0, rows: 0)
        try await withPlayer(songs, source: Self.pageId) { player, fakes in
            let music = YTMusicClient(auth: AuthService(), fetchPage: { _ in response }, persists: false)
            let item = BrowseItem(id: Self.pageId, kind: .album, title: "Oppenheimer", subtitle: "Ludwig Göransson", artworkURL: nil)
            let navigation = NavigationModel()
            navigation.path = [item]
            let hosted = host(BrowseScreen(item: item), player: player, music: music, navigation: navigation, height: 640)
            defer { hosted.window.close() }
            fakes.startPlaying(player)
            // The page loads, its cover's colour lands and the entrances play out.
            await settle(hosted, 40)
            #expect(player.sourceId == Self.pageId && player.isPlaying, "the queue plays from the page")
            #expect(pagesBuilt() > 0, "the page was built to start with")
            let rowsBefore = songs.reduce(0) { $0 + (RowBuildCounts.rows[$1.id] ?? 0) }
            PageBuildCounts.pages[Self.pageId] = nil
            await change(player, hosted)
            await settle(hosted)
            result = (pagesBuilt(), songs.reduce(0) { $0 + (RowBuildCounts.rows[$1.id] ?? 0) } - rowsBefore)
            PageBuildCounts.pages[Self.pageId] = nil
        }
        return result
    }

    @Test func pausingDoesNotRebuildTheAlbumPage() async throws {
        let rebuilt = try await pageRebuilt { player, _ in
            player.togglePlayPause()
            #expect(!player.isPlaying)
        }
        #expect(rebuilt.pages == 0, "only the compact header's disc and the playing row change; the page was built \(rebuilt.pages) times")
        #expect(rebuilt.rows <= 2, "the playing row redraws its pause; the other 23 needn't (\(rebuilt.rows) rebuilt)")
    }

    @Test func hoveringTheHeaderDoesNotRebuildTheAlbumPage() async throws {
        let rebuilt = try await pageRebuilt { _, hosted in
            // The pointer arrives over the compact header's title, as the window would tell each
            // of SwiftUI's tracking areas.
            let point = NSPoint(x: Self.width / 2, y: hosted.hosting.bounds.height - 30)
            for area in hosted.hosting.trackingAreas {
                let entered = NSEvent.enterExitEvent(
                    with: .mouseEntered, location: point, modifierFlags: [], timestamp: 0,
                    windowNumber: hosted.window.windowNumber, context: nil, eventNumber: 0, trackingNumber: area.hash, userData: nil
                )!
                (area.owner as? NSResponder)?.mouseEntered(with: entered)
            }
        }
        #expect(rebuilt.pages == 0, "only the header's title starts its marquee; the page was built \(rebuilt.pages) times")
        #expect(rebuilt.rows == 0, "no song row changes (\(rebuilt.rows) rebuilt)")
    }
}
