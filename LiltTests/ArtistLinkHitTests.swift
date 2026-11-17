import AppKit
import SwiftUI
import Testing
@testable import Lilt

/// The artist name in a row, and the cover in the platter, open their pages when clicked. These
/// host the real views in a window and click them with synthetic mouse events, so a modifier
/// that quietly swallows the click (a parent gesture, a clip that grows a sibling's hit area)
/// shows up as a navigation stack that never changed.
///
/// SwiftUI doesn't expose its accessibility tree in-process, so a target is found by clicking a
/// grid of points over the region where it is laid out and watching for the navigation push.
/// A window that runs a block when closed (the tests close theirs in a `defer`).
private final class RestoringWindow: NSWindow {
    var onClose: (() -> Void)?
    override func close() { super.close(); onClose?(); onClose = nil }
}

@MainActor
struct ArtistLinkHitTests {
    private static let track = Track(
        id: "test-video", title: "Lateralus", artist: "Tool", album: "Lateralus",
        durationText: "9:24", artworkURL: nil, artistId: "UC-tool", albumId: "MPREb-lateralus"
    )

    /// A player whose current track is `track`, seeded through the saved state it restores from
    /// so nothing is sent to the web player (which would really play it). The real app's saved
    /// playback is put back afterwards.
    private static func playerShowing(_ track: Track) -> PlayerService {
        let key = "playbackState"
        let playhead = SavedPlayhead()
        defer { playhead.restore() }
        let real = UserDefaults.standard.data(forKey: key)
        defer { if let real { UserDefaults.standard.set(real, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) } }
        let seeded: [String: Any] = ["queue": [try! JSONSerialization.jsonObject(with: JSONEncoder().encode(track))], "index": 0, "time": 0]
        UserDefaults.standard.set(try! JSONSerialization.data(withJSONObject: seeded), forKey: key)
        return PlayerService(auth: AuthService())
    }

    /// The navigation model persists every change to the shared defaults, which the real app
    /// reads on its next launch; a test's model must leave them as it found them.
    private final class PreservedNavigationState: @unchecked Sendable {
        private let saved = UserDefaults.standard.data(forKey: "navigationState")
        func restore() {
            if let saved { UserDefaults.standard.set(saved, forKey: "navigationState") } else { UserDefaults.standard.removeObject(forKey: "navigationState") }
        }
    }

    /// Hosts `content` with the app's environment in an off-screen window and returns the window
    /// plus the navigation model clicks should land on. Closing the window puts the saved
    /// navigation state back.
    private func host(_ content: some View, size: CGSize, player: PlayerService? = nil) async -> (NSWindow, NavigationModel) {
        let auth = AuthService()
        let preserved = PreservedNavigationState()
        let navigation = NavigationModel()
        navigation.path = []
        navigation.isMiniPlayer = false
        let view = content
            .environment(auth)
            .environment(player ?? PlayerService(auth: auth))
            .environment(YTMusicClient(auth: auth))
            .environment(navigation)
            .environment(ScrollTracker())
            .frame(width: size.width, height: size.height)
        let hosting = NSHostingView(rootView: AnyView(view))
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = RestoringWindow(contentRect: CGRect(origin: CGPoint(x: -10_000, y: -10_000), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.onClose = { preserved.restore() }
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        hosting.layoutSubtreeIfNeeded()
        await settle(8)
        return (window, navigation)
    }

    private func settle(_ frames: Int = 6) async {
        for _ in 0..<frames { try? await Task.sleep(for: .milliseconds(20)) }
    }

    /// A single click at `point`, given in SwiftUI's coordinates (origin top-left).
    private func click(_ point: CGPoint, in window: NSWindow) async {
        let location = CGPoint(x: point.x, y: window.frame.height - point.y)
        let number = Int(Date.timeIntervalSinceReferenceDate * 1000) % 1_000_000
        let time = ProcessInfo.processInfo.systemUptime
        let down = NSEvent.mouseEvent(with: .leftMouseDown, location: location, modifierFlags: [], timestamp: time, windowNumber: window.windowNumber, context: nil, eventNumber: number, clickCount: 1, pressure: 1)!
        let up = NSEvent.mouseEvent(with: .leftMouseUp, location: location, modifierFlags: [], timestamp: time + 0.05, windowNumber: window.windowNumber, context: nil, eventNumber: number + 1, clickCount: 1, pressure: 0)!
        window.sendEvent(down)
        await settle(1)
        window.sendEvent(up)
        await settle(2)
    }

    /// A double-click at `point`: two clicks within the double-click interval, the second counted
    /// as AppKit counts it.
    private func doubleClick(_ point: CGPoint, in window: NSWindow) async {
        let location = CGPoint(x: point.x, y: window.frame.height - point.y)
        let number = Int(Date.timeIntervalSinceReferenceDate * 1000) % 1_000_000
        let time = ProcessInfo.processInfo.systemUptime
        for count in 1...2 {
            let at = time + Double(count - 1) * 0.1
            let down = NSEvent.mouseEvent(with: .leftMouseDown, location: location, modifierFlags: [], timestamp: at, windowNumber: window.windowNumber, context: nil, eventNumber: number + count * 2, clickCount: count, pressure: 1)!
            let up = NSEvent.mouseEvent(with: .leftMouseUp, location: location, modifierFlags: [], timestamp: at + 0.05, windowNumber: window.windowNumber, context: nil, eventNumber: number + count * 2 + 1, clickCount: count, pressure: 0)!
            window.sendEvent(down)
            await settle(1)
            window.sendEvent(up)
            await settle(1)
        }
        await settle(2)
    }

    /// Clicks a grid over `region` until one click pushes `expected`; returns where, if anywhere.
    private func pointOpening(_ expected: String, within region: CGRect, step: CGFloat = 6, in window: NSWindow, navigation: NavigationModel) async -> CGPoint? {
        for y in stride(from: region.minY, through: region.maxY, by: step) {
            for x in stride(from: region.minX, through: region.maxX, by: step) {
                let point = CGPoint(x: x, y: y)
                await click(point, in: window)
                let opened = navigation.path.map(\.id)
                if opened == [expected] { return point }
                if !opened.isEmpty { navigation.path = []; await settle(2) }
            }
        }
        return nil
    }

    /// The harness itself: a bare artist link, clicked where it is, opens the artist.
    @Test func bareArtistLinkOpensTheArtist() async {
        let (window, navigation) = await host(
            ArtistLink(name: "Tool", item: Self.track.artistItem, font: .body).frame(width: 60, height: 30, alignment: .leading),
            size: CGSize(width: 60, height: 30)
        )
        defer { window.close() }
        let hit = await pointOpening("UC-tool", within: CGRect(x: 4, y: 8, width: 24, height: 14), in: window, navigation: navigation)
        #expect(hit != nil, "a bare artist link should open its artist when clicked")
    }

    @Test func artistNameInATrackRowOpensTheArtist() async {
        let (window, navigation) = await host(
            TrackRow(track: Self.track, isCurrent: false, isPlaying: false) {},
            size: CGSize(width: 320, height: 60)
        )
        defer { window.close() }
        // The text column starts after the artwork and the gap; the artist is its lower line.
        let textLeft = Theme.Space.sm + Theme.Size.rowArtwork + Theme.Space.md
        let region = CGRect(x: textLeft, y: 24, width: 40, height: 30)
        let hit = await pointOpening("UC-tool", within: region, in: window, navigation: navigation)
        #expect(hit != nil, "clicking the artist name in a track row should open the artist")
    }

    @Test func artistNameInABrowseRowOpensTheArtist() async {
        var album = BrowseItem(id: "MPREb-lateralus", kind: .album, title: "Lateralus", subtitle: "Album • Tool • 2001", artworkURL: nil)
        album.artist = "Tool"
        album.artistId = "UC-tool"
        let (window, navigation) = await host(BrowseRow(item: album), size: CGSize(width: 320, height: 60))
        defer { window.close() }
        // "Album • " precedes the name; the artist sits a little way into the lower line.
        let textLeft = Theme.Space.sm + Theme.Size.rowArtwork + Theme.Space.md
        let region = CGRect(x: textLeft + 36, y: 24, width: 40, height: 30)
        let hit = await pointOpening("UC-tool", within: region, in: window, navigation: navigation)
        #expect(hit != nil, "clicking the artist name in a browse row should open the artist")
    }

    /// The grid's clicks land a few points and milliseconds apart, so two that miss what they're
    /// looking for can count as a double-click on the platter, which collapses the test host's
    /// own panel to the mini player; the panel is put back afterwards.
    @Test func artistNameInThePlatterOpensTheArtist() async throws {
        let delegate = try #require(AppDelegate.shared, "a double-click among the clicks goes to the app delegate")
        try await withPreservedPanel(delegate) {
            let (window, navigation) = await host(
                NowPlayingBar(), size: CGSize(width: 320, height: 170), player: Self.playerShowing(Self.track)
            )
            defer { window.close() }
            let textLeft = Theme.Space.barPadding + Theme.Size.barArtwork + Theme.Space.md
            let region = CGRect(x: textLeft, y: 20, width: 40, height: 48)
            let hit = await pointOpening("UC-tool", within: region, in: window, navigation: navigation)
            #expect(hit != nil, "clicking the artist name in the platter should open the artist")
        }
    }

    /// Clicks a grid too; see artistNameInThePlatterOpensTheArtist.
    @Test func coverInThePlatterOpensTheAlbum() async throws {
        let delegate = try #require(AppDelegate.shared, "a double-click among the clicks goes to the app delegate")
        try await withPreservedPanel(delegate) {
            let (window, navigation) = await host(
                NowPlayingBar(), size: CGSize(width: 320, height: 170), player: Self.playerShowing(Self.track)
            )
            defer { window.close() }
            let cover = CGRect(x: Theme.Space.barPadding, y: Theme.Space.barPadding, width: Theme.Size.barArtwork, height: Theme.Size.barArtwork)
            let hit = await pointOpening("MPREb-lateralus", within: cover.insetBy(dx: 10, dy: 10), step: 8, in: window, navigation: navigation)
            #expect(hit != nil, "clicking the cover in the platter should open the album")
        }
    }

    /// The tests run inside the app, so the platter's double-click reaches the real delegate and
    /// collapses its window to the mini player; that is observed there and put back afterwards.
    @Test func doubleClickOnEmptyPlatterTogglesTheMiniPlayer() async throws {
        let delegate = try #require(AppDelegate.shared, "the platter's mini toggle goes through the app delegate")
        try await withPreservedPanel(delegate) { await doubleClickToggles(delegate) }
    }

    /// Settings ▸ Playback ▸ Double-click the player: Up Next opens and closes the list instead,
    /// and the window stays expanded.
    @Test func doubleClickCanOpenUpNextInstead() async throws {
        let delegate = try #require(AppDelegate.shared, "the platter's double-click goes through the app delegate")
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: PlatterDoubleClick.key)
        defer { if let saved { defaults.set(saved, forKey: PlatterDoubleClick.key) } else { defaults.removeObject(forKey: PlatterDoubleClick.key) } }
        defaults.set(PlatterDoubleClick.upNext.rawValue, forKey: PlatterDoubleClick.key)
        try await withPreservedPanel(delegate) {
            delegate.setMiniPlayer(false)
            delegate.setQueueVisible(false)
            await settle(4)
            let (window, _) = await host(
                NowPlayingBar(), size: CGSize(width: 320, height: 170), player: Self.playerShowing(Self.track)
            )
            defer { window.close() }
            await doubleClick(CGPoint(x: Theme.Space.barPadding / 2, y: 85), in: window)
            await settle(4)
            #expect(delegate.navigation.isQueueVisible, "double-clicking the platter should open Up Next")
            #expect(!delegate.navigation.isMiniPlayer, "and leave the window expanded")
        }
    }

    private func doubleClickToggles(_ delegate: AppDelegate) async {
        delegate.setMiniPlayer(false)
        await settle(4)
        let (window, navigation) = await host(
            NowPlayingBar(), size: CGSize(width: 320, height: 170), player: Self.playerShowing(Self.track)
        )
        defer { window.close() }
        #expect(!delegate.navigation.isMiniPlayer, "the app should be expanded before the double-click")
        let expandedHeight = delegate.panelFrame.height
        // The padding left of the cover, where nothing takes a click for itself.
        await doubleClick(CGPoint(x: Theme.Space.barPadding / 2, y: 85), in: window)
        await settle(4)
        #expect(delegate.navigation.isMiniPlayer, "double-clicking empty platter should collapse to the mini player")
        // The window is the container: collapsing must shrink it, not only flip the flag.
        await settle(20)
        #expect(delegate.panelFrame.height < expandedHeight, "the window should shrink to the platter; was \(expandedHeight), now \(delegate.panelFrame.height)")
        #expect(navigation.path.isEmpty, "a double-click on empty platter should not open anything")
    }
}
