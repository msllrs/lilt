import AppKit
import SwiftUI
import Testing
@testable import Lilt

/// View ▸ Refresh (⌘R) fetches the screen on top again, through the same path as pulling it down.
@MainActor
struct RefreshCommandTests {
    @Test func theViewMenuHasRefreshOnCommandR() throws {
        let items = NSApp.mainMenu?.items ?? []
        let view = try #require(items.first { $0.title == "View" }?.submenu, "a View menu")
        let refresh = try #require(view.items.first { $0.title == "Refresh" }, "View ▸ Refresh")
        #expect(refresh.keyEquivalent == "r")
        #expect(refresh.keyEquivalentModifierMask.intersection(.deviceIndependentFlagsMask) == .command)

        func all(_ menu: NSMenu) -> [NSMenuItem] { menu.items.flatMap { [$0] + ($0.submenu.map(all) ?? []) } }
        let clashes = items.compactMap(\.submenu).flatMap(all).filter {
            $0 !== refresh && $0.keyEquivalent == "r" && $0.keyEquivalentModifierMask.intersection(.deviceIndependentFlagsMask) == .command
        }
        #expect(clashes.isEmpty, "nothing else takes ⌘R: \(clashes.map(\.title))")
    }

    @Test func refreshFetchesOnlyThePageOnTop() async throws {
        // The navigation model persists every change to the shared defaults, which the real app
        // reads on its next launch; put them back as they were.
        let saved = UserDefaults.standard.data(forKey: "navigationState")
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: "navigationState") } else { UserDefaults.standard.removeObject(forKey: "navigationState") }
        }
        var fetches: [String] = []
        let auth = AuthService()
        let music = YTMusicClient(auth: auth, fetchPage: { id in
            fetches.append(id)
            return JSONObject(value: [:])
        })
        let below = BrowseItem(id: "VL-refresh-below", kind: .playlist, title: "Below", subtitle: "", artworkURL: nil)
        let top = BrowseItem(id: "VL-refresh-top", kind: .playlist, title: "Top", subtitle: "", artworkURL: nil)
        let navigation = NavigationModel()
        navigation.path = [below, top]
        let view = ZStack { BrowseScreen(item: below); BrowseScreen(item: top) }
            .environment(auth)
            .environment(PlayerService(auth: auth))
            .environment(music)
            .environment(navigation)
            .environment(ScrollTracker())
        let panel = PanelWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 320, height: 600))
        panel.contentView = NSHostingView(rootView: view)
        panel.orderFront(nil)
        defer { panel.orderOut(nil); panel.close() }
        await settle(until: { fetches.count == 2 })
        #expect(Set(fetches) == [below.id, top.id], "each page fetches once as it opens")

        navigation.refresh()
        await settle(until: { fetches.count == 3 })
        // Give a wrongly answering page below the chance to fetch too.
        try? await Task.sleep(for: .milliseconds(100))
        #expect(fetches.dropFirst(2) == [top.id], "only the page on top fetches again")
    }

    private func settle(until done: () -> Bool) async {
        for _ in 0..<50 where !done() { try? await Task.sleep(for: .milliseconds(20)) }
    }
}
