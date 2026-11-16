import AppKit
import SwiftUI
import Testing
@testable import Lilt

/// Library shows the first six of each shelf and See All for the rest, which opens the shelf as
/// a page of its own with a field to narrow it, rather than one list of every album and artist.
@MainActor
struct LibraryShelfTests {
    private static func albums(_ count: Int) -> [BrowseItem] {
        (1...count).map { BrowseItem(id: "MPREb-\($0)", kind: .album, title: "Album \($0)", subtitle: "Album • Tool") }
    }

    @Test func aShelfPageIsKnownByItsId() {
        for shelf in LibraryShelf.allCases { #expect(LibraryShelf(page: shelf.page) == shelf) }
        #expect(LibraryShelf(page: NavigationModel.library) == nil, "Library itself isn't a shelf")
    }

    @Test func theFieldNarrowsByTitleOrByline() {
        let items = [
            BrowseItem(id: "a", kind: .album, title: "Ænima", subtitle: "Album • Tool"),
            BrowseItem(id: "b", kind: .album, title: "Lateralus", subtitle: "Album • Tool"),
            BrowseItem(id: "c", kind: .album, title: "White Pony", subtitle: "Album • Deftones"),
        ]
        #expect(LibraryShelf.filtered(items, by: "").map(\.id) == ["a", "b", "c"])
        #expect(LibraryShelf.filtered(items, by: "lateral").map(\.id) == ["b"], "any case")
        #expect(LibraryShelf.filtered(items, by: "deftones").map(\.id) == ["c"], "the byline too")
        #expect(LibraryShelf.filtered(items, by: " tool ").map(\.id) == ["a", "b"], "spaces around it don't count")
    }

    @Test func seeAllOpensTheWholeShelf() async throws {
        let auth = AuthService()
        let music = YTMusicClient(auth: auth, persists: false, library: LibraryContent(albums: Self.albums(10)), fetchAccount: { nil })
        let navigation = NavigationModel()
        let saved = UserDefaults.standard.data(forKey: "navigationState")
        defer { if let saved { UserDefaults.standard.set(saved, forKey: "navigationState") } else { UserDefaults.standard.removeObject(forKey: "navigationState") } }
        navigation.path = [NavigationModel.library]
        let size = CGSize(width: 320, height: 900)
        let view = LibraryScreen(music: music)
            .environment(auth)
            .environment(PlayerService(auth: auth, makeBridge: { FakeBridge() }))
            .environment(music)
            .environment(navigation)
            .environment(ScrollTracker())
            .environment(CollapsedSections())
            .frame(width: size.width, height: size.height)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -10_000, y: -10_000), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderFrontRegardless()
        defer { window.close() }
        for _ in 0..<15 { try await Task.sleep(for: .milliseconds(20)) }

        let albumsPage = LibraryShelf.albums.page
        var opened = false
        for y in stride(from: 60.0, through: 860, by: 12) where !opened {
            click(CGPoint(x: size.width / 2, y: y), in: window)
            try await Task.sleep(for: .milliseconds(30))
            if navigation.path.last?.id == albumsPage.id { opened = true; break }
            // A preview row opens its album: that's not See All, so go back and carry on down.
            if navigation.path.count > 1 { navigation.path = [NavigationModel.library] }
            #expect(navigation.path.last?.id != "MPREb-7", "only six albums are shown before See All")
        }
        #expect(opened, "See All 10 opens the Albums shelf")
    }

    private func click(_ point: CGPoint, in window: NSWindow) {
        let location = CGPoint(x: point.x, y: window.frame.height - point.y)
        let time = ProcessInfo.processInfo.systemUptime
        for (type, offset) in [(NSEvent.EventType.leftMouseDown, 0.0), (.leftMouseUp, 0.05)] {
            window.sendEvent(NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: time + offset, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)!)
        }
    }
}
