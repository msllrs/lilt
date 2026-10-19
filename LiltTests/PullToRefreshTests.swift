import AppKit
import SwiftUI
import Testing
@testable import Lilt

/// Pulling a browse page down past its top fetches it again. SwiftUI's `.refreshable` installs
/// nothing on the Mac, so the page gives its hosted scroll view an `NSRefreshController` itself
/// (macOS 27); this checks the controller is there and that its action reaches the server.
@MainActor
struct PullToRefreshTests {
    @Test func pullingABrowsePageFetchesItAgain() async throws {
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

        let controller = try #require(findScrollView(in: panel.contentView)?.refreshController, "the browse list's scroll view has a refresh controller")
        let action = try #require(controller.action)
        controller.beginRefreshing()
        NSApp.sendAction(action, to: controller.target, from: controller)
        await settle(until: { fetches == 2 && !controller.isRefreshing })
        #expect(fetches == 2, "pulling fetches the page again")
        #expect(!controller.isRefreshing, "the indicator goes away once the fetch is done")
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
