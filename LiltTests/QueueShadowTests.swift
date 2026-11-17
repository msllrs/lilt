import AppKit
import SwiftUI
import Testing
@testable import Lilt

/// A cover in the Up Next list casts the same soft shadow as a cover anywhere else: the list's
/// clips (the cut below the last row's gutter, the table's cells) must not square it off. These
/// render the real list in an off-screen window and compare the pixels just outside its first
/// cover with the same spots around a bare cover drawn on its own.
@MainActor
struct QueueShadowTests {
    /// Room around the list, so a shadow spilling past it has somewhere to show.
    private static let margin: CGFloat = 24
    private static let size = CGSize(width: 320, height: 200)
    /// The cover is 28pt in the list.
    private static let cover: CGFloat = 28

    /// A saturated cover, so its shadow stands out against the white behind it.
    private static func coverURL() -> URL {
        let url = URL(string: "https://lh3.googleusercontent.com/test-queue-shadow-cover=w120-h120-l90-rj")!
        if ImageCache.shared.cached(url) == nil {
            let image = NSImage(size: NSSize(width: 120, height: 120), flipped: false) { rect in
                NSColor(red: 0.85, green: 0.1, blue: 0.1, alpha: 1).setFill()
                rect.fill()
                return true
            }
            ImageCache.shared.store(image, for: url)
        }
        return url
    }

    /// A player with three songs queued by hand: the first with a cover, the others without (a
    /// placeholder casts no shadow), so the first cover's shadow is the only one around it.
    /// The real app's saved playback is put back afterwards.
    private func withQueue(_ body: (PlayerService) async -> Void) async throws {
        let key = "playbackState"
        let playhead = SavedPlayhead()
        defer { playhead.restore() }
        let saved = UserDefaults.standard.data(forKey: key)
        defer { if let saved { UserDefaults.standard.set(saved, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) } }
        let now = Track(id: "now", title: "Now", artist: "Tool")
        let state: [String: Any] = ["queue": [try JSONSerialization.jsonObject(with: JSONEncoder().encode(now))], "index": 0, "time": 0]
        UserDefaults.standard.set(try JSONSerialization.data(withJSONObject: state), forKey: key)
        let player = PlayerService(auth: AuthService())
        player.enqueue(Track(id: "red", title: "Schism", artist: "Tool", artworkURL: Self.coverURL()))
        player.enqueue(Track(id: "blank1", title: "Parabola", artist: "Tool"))
        player.enqueue(Track(id: "blank2", title: "Ticks & Leeches", artist: "Tool"))
        await body(player)
    }

    /// The navigation model persists every change to the shared defaults; put them back.
    private final class PreservedNavigationState: @unchecked Sendable {
        private let saved = UserDefaults.standard.data(forKey: "navigationState")
        func restore() {
            if let saved { UserDefaults.standard.set(saved, forKey: "navigationState") } else { UserDefaults.standard.removeObject(forKey: "navigationState") }
        }
    }

    /// Renders `content`, inset by `margin` on a white ground, in an off-screen window, after
    /// handing the laid-out view to `inspect`.
    @discardableResult
    private func render(_ content: some View, player: PlayerService, inspect: (NSView) -> Void = { _ in }) async -> NSBitmapImageRep {
        let auth = AuthService()
        let preserved = PreservedNavigationState()
        defer { preserved.restore() }
        let navigation = NavigationModel()
        let view = content
            .padding(Self.margin)
            .frame(width: Self.size.width, height: Self.size.height, alignment: .top)
            .background(Color.white)
            .environment(\.colorScheme, .light)
            .environment(auth)
            .environment(player)
            .environment(YTMusicClient(auth: auth))
            .environment(navigation)
            .environment(ScrollTracker())
        let hosting = NSHostingView(rootView: AnyView(view))
        hosting.frame = CGRect(origin: .zero, size: Self.size)
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -10_000, y: -10_000), size: Self.size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = hosting
        window.orderFront(nil)
        defer { window.close() }
        for _ in 0..<15 {
            hosting.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(20))
        }
        inspect(hosting)
        let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)!
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        return rep
    }

    /// How far a pixel, given in points from the top left, is from the white ground (0 to 1), by
    /// its most changed channel: a red cover's shadow barely moves the red.
    private func darkness(_ rep: NSBitmapImageRep, _ point: CGPoint) -> CGFloat {
        let scale = CGFloat(rep.pixelsWide) / Self.size.width
        guard let color = rep.colorAt(x: Int(point.x * scale), y: Int(point.y * scale))?.usingColorSpace(.sRGB) else { return 0 }
        return 1 - min(color.redComponent, color.greenComponent, color.blueComponent)
    }

    /// The spots to compare, relative to the cover's top-left corner: a few points left of its
    /// middle, and a point past the bottom of its 40pt row (the shadow is faint by then, but a
    /// cut leaves nothing at all).
    private static let beside = CGPoint(x: -3, y: cover / 2)
    private static let below = CGPoint(x: cover / 2, y: cover + QueueList.rowGutter + 1)

    @Test func coverShadowSpillsPastTheListAndItsRow() async throws {
        let url = Self.coverURL()
        try await withQueue { player in
            // The bare cover, where nothing clips its shadow.
            let reference = await render(
                ArtworkView(url: url, size: Self.cover, radius: Theme.Radius.artwork(Self.cover), context: .row)
                    .frame(maxWidth: .infinity, alignment: .leading),
                player: player
            )
            let list = await render(QueueList(), player: player)

            // The bare cover sits at the margin; in the list, below the divider and the gutter
            // above the first row.
            let bareOrigin = CGPoint(x: Self.margin, y: Self.margin)
            let listOrigin = CGPoint(x: Self.margin, y: Self.margin + QueueList.dividerHeight + QueueList.rowGutter)

            // Sanity: the cover itself drew in both, where it was expected.
            let centre = CGPoint(x: Self.cover / 2, y: Self.cover / 2)
            #expect(darkness(reference, bareOrigin + centre) > 0.3, "the bare cover should draw")
            #expect(darkness(list, listOrigin + centre) > 0.3, "the list's first cover should draw")

            for (name, spot) in [("left of", Self.beside), ("below the row of", Self.below)] {
                let expected = darkness(reference, bareOrigin + spot)
                let actual = darkness(list, listOrigin + spot)
                #expect(expected > 0.01, "a bare cover's shadow should show \(name) it (got \(expected))")
                #expect(actual > expected * 0.7, "the queue's shadow \(name) the cover is cut off: \(actual) against \(expected) for a bare cover")
            }
        }
    }
}

extension QueueShadowTests {
    /// The cover is drawn by a view of its own (so its shadow can leave the row); clicks on it
    /// must still reach the row, as they reach the title beside it.
    @Test func coverStillPassesClicksToItsRow() async throws {
        try await withQueue { player in
            await render(QueueList(), player: player) { hosting in
                // AppKit's coordinates: origin bottom left.
                let middle = Self.size.height - (Self.margin + QueueList.dividerHeight + QueueList.rowGutter + Self.cover / 2)
                let onCover = hosting.hitTest(NSPoint(x: Self.margin + Self.cover / 2, y: middle))
                let onTitle = hosting.hitTest(NSPoint(x: Self.margin + Self.cover * 2, y: middle))
                #expect(onCover != nil)
                #expect(onCover === onTitle, "a click on the cover went to \(onCover.map { String(describing: type(of: $0)) } ?? "nothing"), not the row")
            }
        }
    }
}

private func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
