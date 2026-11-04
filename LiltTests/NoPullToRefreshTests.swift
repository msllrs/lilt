import AppKit
import SwiftUI
import Testing
@testable import Lilt

/// Browse pages don't refresh on a pull: their scroll view has no `NSRefreshController`, so a
/// pull past the top only bounces. ⌘R (and a playlist's ⋯ menu) is the way to refresh.
@MainActor
struct NoPullToRefreshTests {
    @Test func aPlaylistPageCannotBePulledToRefresh() async throws {
        guard #available(macOS 27, *) else { return }
        var fetches = 0
        let auth = AuthService()
        let music = YTMusicClient(auth: auth, fetchPage: { _ in
            fetches += 1
            return JSONObject(value: ["header": ["musicResponsiveHeaderRenderer": ["title": ["runs": [["text": "Liked Music"]]]]]])
        })
        let item = BrowseItem(id: "VLLM-pull-test", kind: .playlist, title: "Liked Music", subtitle: "", artworkURL: nil)
        let view = BrowseScreen(item: item)
            .environment(auth)
            .environment(PlayerService(auth: auth))
            .environment(music)
            .environment(NavigationModel())
            .environment(ScrollTracker())
        let panel = PanelWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 320, height: 600))
        panel.contentView = NSHostingView(rootView: view)
        panel.orderFront(nil)
        defer { panel.orderOut(nil); panel.close() }
        await settle(until: { fetches == 1 })
        #expect(fetches == 1, "opening the page fetches it")

        let scrollView = try #require(findScrollView(in: panel.contentView), "the browse list's scroll view")
        #expect(scrollView.refreshController == nil, "a pull past the top doesn't refresh")
    }

    private func settle(until done: () -> Bool) async {
        for _ in 0..<50 where !done() { try? await Task.sleep(for: .milliseconds(20)) }
    }

    private func findScrollView(in view: NSView?) -> NSScrollView? {
        guard let view else { return nil }
        if let scroll = view as? NSScrollView { return scroll }
        for sub in view.subviews { if let found = findScrollView(in: sub) { return found } }
        return nil
    }
}
