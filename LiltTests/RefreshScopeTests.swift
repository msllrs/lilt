import AppKit
import SwiftUI
import Testing
@testable import Lilt

/// Refreshing is for pages that gain songs elsewhere (a song liked on the phone): playlists.
/// Albums don't change once released, so an album page offers neither the pull nor ⌘R.
@MainActor
struct RefreshScopeTests {
    @Test func anAlbumPageDoesNotRefresh() async throws {
        // The navigation model persists every change to the shared defaults, which the real app
        // reads on its next launch; put them back as they were.
        let saved = UserDefaults.standard.data(forKey: "navigationState")
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: "navigationState") } else { UserDefaults.standard.removeObject(forKey: "navigationState") }
        }
        var fetches = 0
        let auth = AuthService()
        let music = YTMusicClient(auth: auth, fetchPage: { _ in
            fetches += 1
            return JSONObject(value: [:])
        })
        let album = BrowseItem(id: "MPREb-refresh-scope", kind: .album, title: "Album", subtitle: "", artworkURL: nil)
        let navigation = NavigationModel()
        navigation.path = [album]
        let view = BrowseScreen(item: album)
            .environment(auth)
            .environment(PlayerService(auth: auth))
            .environment(music)
            .environment(navigation)
            .environment(ScrollTracker())
        let panel = PanelWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 320, height: 600))
        panel.contentView = NSHostingView(rootView: view)
        panel.orderFront(nil)
        defer { panel.orderOut(nil); panel.close() }
        await settle(until: { fetches == 1 })
        #expect(fetches == 1, "opening the page fetches it")

        if #available(macOS 27, *) {
            #expect(findScrollView(in: panel.contentView)?.refreshController == nil, "an album list can't be pulled to refresh")
        }
        navigation.refresh()
        try? await Task.sleep(for: .milliseconds(200))
        #expect(fetches == 1, "⌘R leaves an album page alone")
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
