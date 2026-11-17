import AppKit
import SwiftUI
import Testing
@testable import Lilt

/// As Up Next opens, or is dragged out, the platter grows a step every frame and the column's
/// list makes room under it. Only the screen on top needs to: a page parked beneath another
/// keeps the room it had and catches up when it comes back on top, rather than having its list
/// laid out again every frame of a queue it can't be seen under. Counted by each page's reports
/// of its scroll changing, which a change of the room under its list sets off.
@MainActor
struct ParkedScreenInsetTests {
    private static let size = CGSize(width: 320, height: 640)
    private static let parkedId = "MPREb-parked-inset-under"
    private static let topId = "MPREb-parked-inset-top"

    @Test func onlyTheScreenOnTopMakesRoomAsThePlatterGrows() async throws {
        let delegate = try #require(AppDelegate.shared, "the column takes the app's recents and ambience")
        let keys = ["navigationState", "playbackState", PlayerService.playheadKey]
        let saved = keys.map { UserDefaults.standard.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, saved) {
                if let value { UserDefaults.standard.set(value, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
            }
        }
        // A song loaded, so the platter is there and the column leaves room for it.
        let song = Track(id: "parked-inset-song", title: "Song", artist: "Tool")
        let state: [String: Any] = ["queue": [try JSONSerialization.jsonObject(with: JSONEncoder().encode(song))], "index": 0, "time": 0]
        UserDefaults.standard.set(try JSONSerialization.data(withJSONObject: state), forKey: "playbackState")
        let auth = AuthService()
        let player = PlayerService(auth: auth, makeBridge: { FakeBridge() })
        let response = AlbumScrollTests.albumResponse(tracks: 24, carousels: [])
        let music = YTMusicClient(auth: auth, fetchPage: { _ in response }, persists: false)
        let album = { (id: String) in BrowseItem(id: id, kind: .album, title: "Oppenheimer", subtitle: "Ludwig Göransson", artworkURL: nil) }
        let navigation = NavigationModel()
        navigation.isMiniPlayer = false
        navigation.path = [album(Self.parkedId), album(Self.topId)]

        let view = RootView()
            .environment(\.colorScheme, .light)
            .environment(auth)
            .environment(player)
            .environment(music)
            .environment(navigation)
            .environment(ScrollTracker())
            .environment(delegate.recents)
            .environment(CollapsedSections())
            .environment(delegate.ambience)
            .environment(NoticeCenter())
            .environment(PanelRest(schedule: { _, _ in {} }, isButtonDown: { false }))
            .frame(width: Self.size.width, height: Self.size.height)
        let hosting = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(origin: CGPoint(x: -10_000, y: -10_000), size: Self.size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderFrontRegardless()
        defer { window.close() }
        func settle(_ steps: Int) async {
            for _ in 0..<steps {
                hosting.layoutSubtreeIfNeeded()
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
        await settle(40)
        #expect(player.current != nil, "the platter is up")
        #expect(PageBuildCounts.visibleHeights[Self.parkedId] != nil && PageBuildCounts.visibleHeights[Self.topId] != nil, "both pages are laid out")

        // Up Next opening: the platter grows by 6 points a frame for 20 frames.
        PageBuildCounts.scrollReports[Self.parkedId] = nil
        PageBuildCounts.scrollReports[Self.topId] = nil
        let before = PageBuildCounts.visibleHeights[Self.topId] ?? 0
        let start = navigation.platterHeight
        for step in 1...20 {
            navigation.platterHeight = start + CGFloat(step * 6)
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(16))
        }
        await settle(10)
        let parked = PageBuildCounts.scrollReports[Self.parkedId] ?? 0
        let top = PageBuildCounts.scrollReports[Self.topId] ?? 0
        let shown = PageBuildCounts.visibleHeights[Self.topId] ?? 0
        print("ParkedScreenInset: parked page reported \(parked) times, top page \(top), top's list \(before) -> \(shown)")
        #expect(before - shown >= 120, "the page on top makes room for the 120 points (its list went from \(before) to \(shown))")
        #expect(top >= 10, "and follows the platter as it grows (\(top) reports)")
        #expect(parked <= 1, "the page beneath isn't laid out again for a platter it can't be seen under (\(parked) reports)")

        // Back to the page beneath: it makes the same room as the one on top had.
        navigation.path = [album(Self.parkedId)]
        await settle(40)
        let caughtUp = PageBuildCounts.visibleHeights[Self.parkedId] ?? 0
        #expect(abs(caughtUp - shown) < 1, "back on top, the page leaves room for the platter as it is now (its list shows \(caughtUp), the other page's \(shown))")
        PageBuildCounts.scrollReports[Self.parkedId] = nil
        PageBuildCounts.scrollReports[Self.topId] = nil
    }
}
