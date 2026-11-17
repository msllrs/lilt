import AppKit
import Observation
import SwiftUI
import Testing
@testable import Lilt

/// Scrolling an album page through the hero's hand-off changes only what follows the scroll.
/// The back button's light climbs its edge as the compact header rises, frame by frame, without
/// the button itself, its glyph's palette and the cover's colours being worked out again each
/// frame; and on a short album, whose page is padded out so the hero can always scroll away,
/// the padding following the list's estimate of its height doesn't rebuild the page.
@MainActor
struct PageScrollInvalidationTests {
    private static let size = CGSize(width: 320, height: 640)

    /// The page and the back button over its top-left corner, as the navigation column has them.
    private struct Column: View {
        let item: BrowseItem
        var body: some View {
            BrowseScreen(item: item)
                .overlay(alignment: .topLeading) {
                    LeadingButton(isBack: true)
                        .padding(.top, Theme.Space.panelInset)
                        .padding(.leading, Theme.Space.panelInset)
                }
        }
    }

    struct Scrolled {
        var pages = 0
        var buttons = 0
        var castWrites = 0
        var tintWrites = 0
        var amounts: [Double] = []
    }

    /// An album of `tracks` songs scrolled from the top through `distance` points, 20 a step;
    /// what the steps rebuilt and wrote.
    private func scroll(_ id: String, tracks: Int, distance: CGFloat = 360) async throws -> Scrolled {
        let saved = UserDefaults.standard.data(forKey: "navigationState")
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: "navigationState") } else { UserDefaults.standard.removeObject(forKey: "navigationState") }
        }
        let auth = AuthService()
        let response = AlbumScrollTests.albumResponse(tracks: tracks, carousels: [])
        let music = YTMusicClient(auth: auth, fetchPage: { _ in response }, persists: false)
        let item = BrowseItem(id: id, kind: .album, title: "Oppenheimer", subtitle: "Ludwig Göransson", artworkURL: nil)
        let navigation = NavigationModel()
        navigation.path = [item]
        let view = Column(item: item)
            .environment(\.colorScheme, .light)
            .environment(auth)
            .environment(PlayerService(auth: auth, makeBridge: { FakeBridge() }))
            .environment(music)
            .environment(navigation)
            .environment(ScrollTracker())
            .environment(CollapsedSections())
            .frame(width: Self.size.width, height: Self.size.height)
        let hosting = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(origin: CGPoint(x: -10_000, y: -10_000), size: Self.size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderFrontRegardless()
        defer { window.close() }
        // The page loads, the cover's colours land and the entrances play out.
        for _ in 0..<40 {
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(25))
        }
        let scrollView = try #require(findScrollView(in: hosting), "the page's list is an NSScrollView")
        let clip = scrollView.contentView

        var result = Scrolled()
        // Every change to the colours the page hands the back button, followed as it lands.
        let cast = Writes { _ = navigation.leadingCast }
        let tint = Writes { _ = navigation.leadingTintAccent }
        defer { cast.stop(); tint.stop() }
        PageBuildCounts.pages[id] = nil
        PageBuildCounts.leadingButtons = 0

        var y = clip.bounds.origin.y
        for _ in 0..<Int(distance / 20) {
            y += 20
            clip.scroll(to: NSPoint(x: 0, y: y))
            scrollView.reflectScrolledClipView(clip)
            hosting.layoutSubtreeIfNeeded()
            hosting.displayIfNeeded()
            try await Task.sleep(for: .milliseconds(16))
            result.amounts.append(navigation.leadingCastAmount)
        }
        try await Task.sleep(for: .milliseconds(50))
        result.castWrites = cast.count
        result.tintWrites = tint.count
        result.pages = PageBuildCounts.pages[id] ?? 0
        result.buttons = PageBuildCounts.leadingButtons
        PageBuildCounts.pages[id] = nil
        return result
    }

    /// Counts the changes to what `read` reads, following each as it lands.
    @MainActor private final class Writes {
        private(set) var count = 0
        private var watching = true
        private let read: @MainActor () -> Void

        init(_ read: @escaping @MainActor () -> Void) {
            self.read = read
            watch()
        }

        func stop() { watching = false }

        private func watch() {
            withObservationTracking { read() } onChange: { [weak self] in
                Task { @MainActor in
                    guard let self, self.watching else { return }
                    self.count += 1
                    self.watch()
                }
            }
        }
    }

    private func findScrollView(in view: NSView?) -> NSScrollView? {
        guard let view else { return nil }
        if let scroll = view as? NSScrollView { return scroll }
        for sub in view.subviews { if let found = findScrollView(in: sub) { return found } }
        return nil
    }

    @Test func theHandOffMovesTheBackButtonsLightAlone() async throws {
        let scrolled = try await scroll("MPREb-scroll-invalidation-handoff", tracks: 24)
        print("PageScrollInvalidation hand-off: button built \(scrolled.buttons) times, cast written \(scrolled.castWrites), tint \(scrolled.tintWrites), amounts \(scrolled.amounts.map { String(format: "%.2f", $0) })")
        #expect(scrolled.amounts.last ?? 0 > 0.99, "the scroll should carry the header all the way in (\(scrolled.amounts.last ?? 0))")
        #expect(Set(scrolled.amounts).count > 4, "the light climbs the edge step by step")
        #expect(scrolled.buttons <= 1, "only the light follows the scroll; the back button was built \(scrolled.buttons) times")
        #expect(scrolled.castWrites == 0 && scrolled.tintWrites == 0, "the cover's colours are the same all the way; cast written \(scrolled.castWrites) times, tint \(scrolled.tintWrites)")
    }

    @Test func scrollingAShortAlbumDoesNotRebuildThePage() async throws {
        let scrolled = try await scroll("MPREb-scroll-invalidation-short", tracks: 4)
        print("PageScrollInvalidation short album: page built \(scrolled.pages) times over \(scrolled.amounts.count) steps")
        #expect(scrolled.amounts.last ?? 0 > 0.99, "even a short album scrolls the hero away (\(scrolled.amounts.last ?? 0))")
        #expect(scrolled.pages == 0, "a scroll moves the hero and the header, not the page; it was built \(scrolled.pages) times")
    }
}
