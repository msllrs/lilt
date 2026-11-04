import AppKit
import SwiftUI
import Testing
@testable import Lilt

/// Scrolling an album page, as Matt recorded it: the Oppenheimer soundtrack's hero, 24 tracks
/// and two related carousels, with the platter over the list, in light mode on the panel's own
/// window. The page is scrolled 12pt a step, as a trackpad does at a steady pace, from the hero
/// through the tracks to the related sections, 120 steps, and each step's
/// main-thread cost is timed with a 1ms heartbeat: the update and layout the scroll asks for,
/// the frame's display and commit, and whatever SwiftUI runs after it before the next step.
@MainActor
struct AlbumScrollTests {
    private static let size = CGSize(width: 320, height: 640)
    private static let albumId = "MPREb-album-scroll"

    /// A cover in the cache for `id`, so nothing waits on the network.
    private static func cover(_ id: String, hue: Double) -> String {
        let raw = "https://lh3.googleusercontent.com/album-scroll-\(id)=w544-h544-l90-rj"
        for size in [240, 480, 544] {
            let url = SearchParser.artworkURL(raw, size: size)!
            if ImageCache.shared.cached(url) == nil {
                let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
                    NSColor(hue: hue, saturation: 0.5, brightness: 0.7, alpha: 1).setFill()
                    rect.fill()
                    return true
                }
                ImageCache.shared.store(image, for: url)
            }
        }
        return raw
    }

    private static func run(_ text: String, browseId: String? = nil, pageType: String? = nil) -> [String: Any] {
        guard let browseId else { return ["text": text] }
        var endpoint: [String: Any] = ["browseId": browseId]
        if let pageType {
            endpoint["browseEndpointContextSupportedConfigs"] = ["browseEndpointContextMusicConfig": ["pageType": pageType]]
        }
        return ["text": text, "navigationEndpoint": ["browseEndpoint": endpoint]]
    }

    private static func thumbnails(_ url: String) -> [String: Any] {
        ["musicThumbnailRenderer": ["thumbnail": ["thumbnails": [["url": url, "width": 544, "height": 544]]]]]
    }

    /// An album response the parser reads as the real one: the header, `tracks` rows and
    /// `carousels` shelves of albums.
    static func albumResponse(tracks: Int = 24, carousels: [String] = ["Releases for you", "More from Ludwig Göransson"]) -> JSONObject {
        let artist = run("Ludwig Göransson", browseId: "UC-album-scroll-artist", pageType: "MUSIC_PAGE_TYPE_ARTIST")
        let header: [String: Any] = [
            "title": ["runs": [["text": "Oppenheimer (Original Motion Picture Soundtrack)"]]],
            "straplineTextOne": ["runs": [artist]],
            "subtitle": ["runs": [["text": "Album • 2023"]]],
            "thumbnail": thumbnails(cover("hero", hue: 0.07)),
            "buttons": [["musicPlayButtonRenderer": ["playNavigationEndpoint": ["watchPlaylistEndpoint": ["playlistId": "OLAK5uy-album-scroll"]]]]],
        ]
        let rows: [[String: Any]] = (0..<tracks).map { i in
            ["musicResponsiveListItemRenderer": [
                "playlistItemData": ["videoId": "album-scroll-\(i)"],
                "flexColumns": [
                    ["musicResponsiveListItemFlexColumnRenderer": ["text": ["runs": [["text": "Track \(i + 1) of the Score, a Long Title"]]]]],
                    ["musicResponsiveListItemFlexColumnRenderer": ["text": ["runs": [artist]]]],
                ],
                "fixedColumns": [["musicResponsiveListItemFixedColumnRenderer": ["text": ["runs": [["text": "\(1 + i % 5):\(10 + i)"]]]]]],
            ]]
        }
        let shelves: [[String: Any]] = carousels.enumerated().map { s, title in
            ["musicCarouselShelfRenderer": [
                "header": ["musicCarouselShelfBasicHeaderRenderer": ["title": ["runs": [["text": title]]]]],
                "contents": (0..<8).map { i -> [String: Any] in
                    var two: [String: Any] = [
                        "title": ["runs": [["text": "Album \(s)-\(i)"]]],
                        "subtitle": ["runs": [["text": "Album • "], artist]],
                        "thumbnailRenderer": thumbnails(cover("related-\(s)-\(i)", hue: Double(i) / 8)),
                    ]
                    two["navigationEndpoint"] = run("", browseId: "MPREb-album-scroll-\(s)-\(i)", pageType: "MUSIC_PAGE_TYPE_ALBUM")["navigationEndpoint"]
                    return ["musicTwoRowItemRenderer": two]
                },
            ]]
        }
        return JSONObject(value: [
            "header": ["musicResponsiveHeaderRenderer": header],
            "contents": ["musicShelfRenderer": ["contents": rows], "carousels": shelves],
        ])
    }

    /// A player with a song from the album loaded, so the platter shows, on a fake web player.
    private static func playerShowing() -> PlayerService {
        let track = Track(id: "album-scroll-0", title: "Can You Hear the Music", artist: "Ludwig Göransson",
                          album: "Oppenheimer", durationText: "1:50", artworkURL: URL(string: cover("hero", hue: 0.07)),
                          artistId: "UC-album-scroll-artist", albumId: albumId)
        let saved = UserDefaults.standard.data(forKey: "playbackState")
        defer { if let saved { UserDefaults.standard.set(saved, forKey: "playbackState") } else { UserDefaults.standard.removeObject(forKey: "playbackState") } }
        let state: [String: Any] = ["queue": [try! JSONSerialization.jsonObject(with: JSONEncoder().encode(track))], "index": 0, "time": 0]
        UserDefaults.standard.set(try! JSONSerialization.data(withJSONObject: state), forKey: "playbackState")
        return PlayerService(auth: AuthService(), makeBridge: { FakeBridge() })
    }

    /// The panel's column reduced to the page and the platter over it, as RootView stacks them.
    private struct Panel: View {
        let item: BrowseItem
        @Environment(NavigationModel.self) private var navigation
        var body: some View {
            ZStack(alignment: .bottom) {
                Color.clear
                    .overlay { PanelBackground() }
                    .allowsHitTesting(false)
                BrowseScreen(item: item)
                    .safeAreaBar(edge: .bottom, spacing: 0) {
                        Color.clear.frame(height: navigation.platterHeight + Theme.Space.panelInset)
                    }
                NowPlayingBar()
                    .padding(.horizontal, Theme.Space.panelInset)
                    .padding(.bottom, Theme.Space.panelInset)
            }
        }
    }

    struct Step { var sync: Double; var after: Double; var total: Double { sync + after } }

    private func scroll(steps: Int = 120, by delta: CGFloat = 12) async throws -> [Step] {
        let saved = UserDefaults.standard.data(forKey: "navigationState")
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: "navigationState") } else { UserDefaults.standard.removeObject(forKey: "navigationState") }
        }
        let auth = AuthService()
        let response = Self.albumResponse()
        let music = YTMusicClient(auth: auth, fetchPage: { _ in response }, persists: false)
        let item = BrowseItem(id: Self.albumId, kind: .album, title: "Oppenheimer", subtitle: "Ludwig Göransson", artworkURL: URL(string: Self.cover("hero", hue: 0.07)))
        let navigation = NavigationModel()
        navigation.path = [item]
        navigation.isMiniPlayer = false
        let view = Panel(item: item)
            .environment(\.colorScheme, .light)
            .environment(auth)
            .environment(Self.playerShowing())
            .environment(music)
            .environment(navigation)
            .environment(ScrollTracker())
            .environment(CollapsedSections())
            .frame(width: Self.size.width, height: Self.size.height)
        let hosting = NSHostingView(rootView: view)
        let panel = PanelWindow(contentRect: NSRect(origin: CGPoint(x: -10_000, y: -10_000), size: Self.size))
        panel.appearance = NSAppearance(named: .aqua)
        panel.contentView = hosting
        panel.orderFront(nil)
        defer { panel.orderOut(nil); panel.close() }
        // The page loads, the covers' colours land and the entrances play out.
        for _ in 0..<40 {
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(25))
        }
        let scrollView = try #require(findScrollView(in: hosting), "the page's list is an NSScrollView")
        let clip = scrollView.contentView
        let documentHeight = scrollView.documentView?.frame.height ?? 0
        #expect(documentHeight > Self.size.height + CGFloat(steps) * delta, "the page should be long enough to scroll \(CGFloat(steps) * delta)pt (\(documentHeight)pt)")

        let heart = LibraryArrivalTests.Heartbeat()
        defer { heart.stop() }
        try await Task.sleep(for: .milliseconds(50))
        var results: [Step] = []
        var y = clip.bounds.origin.y
        for _ in 0..<steps {
            let start = heart.now()
            y += delta
            clip.scroll(to: NSPoint(x: 0, y: y))
            scrollView.reflectScrolledClipView(clip)
            hosting.layoutSubtreeIfNeeded()
            hosting.displayIfNeeded()
            CATransaction.flush()
            let synced = heart.now()
            // A 60Hz frame later, the next step; anything SwiftUI ran in between counts too.
            try await Task.sleep(for: .milliseconds(16))
            let after = heart.spells(after: synced, over: 2).filter { $0.at >= synced - 2 }.reduce(0) { $0 + $1.ms }
            results.append(Step(sync: synced - start, after: after))
        }
        return results
    }

    private func findScrollView(in view: NSView?) -> NSScrollView? {
        guard let view else { return nil }
        if let scroll = view as? NSScrollView { return scroll }
        for sub in view.subviews { if let found = findScrollView(in: sub) { return found } }
        return nil
    }

    /// Scrolling has to keep up with the display: half a 60Hz frame at the median, with room to
    /// spare for the render server, and a missed frame only now and then, as a row comes into
    /// view and is built (about every fourth step, 9 to 16ms in a Debug build), never the runs of
    /// them in the recording. No step may hold the main thread for two frames. The page is
    /// scrolled three times and judged by its best run: alongside the rest of the suite, other
    /// tests' main-actor work lands between the steps and counts against them, where a slow page
    /// is slow every time.
    @Test func scrollingAnAlbumPageFitsInAFrame() async throws {
        _ = try await scroll(steps: 10) // type metadata, fonts and symbol images, once
        let frame = 1000 / 60.0
        struct Run { var median: Double; var missed: Int; var worst: Double; var count: Int }
        var runs: [Run] = []
        for _ in 0..<3 {
            let steps = try await scroll()
            let totals = steps.map(\.total).sorted()
            let run = Run(median: totals[totals.count / 2], missed: totals.filter { $0 > frame }.count, worst: totals.last ?? 0, count: steps.count)
            print(String(format: "AlbumScroll: median %.1fms, p90 %.1fms, worst %.1fms per 12pt step, %d of %d over a frame (sync median %.1fms, after median %.1fms)",
                         run.median, totals[totals.count * 9 / 10], run.worst, run.missed, run.count,
                         steps.map(\.sync).sorted()[steps.count / 2], steps.map(\.after).sorted()[steps.count / 2]))
            print("AlbumScroll steps: " + steps.map { String(format: "%.1f+%.1f", $0.sync, $0.after) }.joined(separator: " "))
            runs.append(run)
        }
        let best = runs.min { ($0.missed, $0.median) < ($1.missed, $1.median) }!
        #expect(best.median <= frame / 2, "a scroll step's median main-thread cost was \(best.median)ms, over half a frame")
        #expect(best.missed <= best.count / 20, "\(best.missed) of \(best.count) scroll steps held the main thread over a 60Hz frame")
        #expect(best.worst <= 2 * frame, "the worst scroll step held the main thread \(best.worst)ms, over two 60Hz frames")
    }
}
