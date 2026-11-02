import AppKit
import SwiftUI
import Testing
@testable import Lilt

/// An album page's title takes its cover's colour; a playlist's, with the same cover, stays the
/// plain label. These render the real page off-screen and look at the title's own strokes.
@MainActor
struct AlbumCoverTintRenderTests {
    private static let size = CGSize(width: 320, height: 420)

    /// A saturated red cover, so a tinted title is plainly red and a plain one plainly not.
    private static func coverURL() -> URL {
        let url = URL(string: "https://lh3.googleusercontent.com/test-album-cover-tint=w544-h544-l90-rj")!
        if ImageCache.shared.cached(url) == nil {
            let image = NSImage(size: NSSize(width: 120, height: 120), flipped: false) { rect in
                NSColor(srgbRed: 0.85, green: 0.1, blue: 0.1, alpha: 1).setFill()
                rect.fill()
                return true
            }
            ImageCache.shared.store(image, for: url)
        }
        return url
    }

    /// Renders the page for a `kind` with the red cover, on white, in light mode. The fetch
    /// answers with nothing, so only the header (from the item itself) has anything to show.
    private func render(_ kind: BrowseKind) async -> NSBitmapImageRep {
        let saved = UserDefaults.standard.data(forKey: "navigationState")
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: "navigationState") } else { UserDefaults.standard.removeObject(forKey: "navigationState") }
        }
        let auth = AuthService()
        let music = YTMusicClient(auth: auth, fetchPage: { _ in JSONObject(value: [:]) })
        let item = BrowseItem(id: "cover-tint-\(kind.rawValue)", kind: kind, title: "WWWWWWWW", subtitle: "", artworkURL: Self.coverURL())
        let navigation = NavigationModel()
        navigation.path = [item]
        let view = BrowseScreen(item: item)
            .frame(width: Self.size.width, height: Self.size.height)
            .background(Color.white)
            .environment(\.colorScheme, .light)
            .environment(auth)
            .environment(PlayerService(auth: auth))
            .environment(music)
            .environment(navigation)
            .environment(ScrollTracker())
            .environment(CollapsedSections())
        let hosting = NSHostingView(rootView: AnyView(view))
        hosting.frame = CGRect(origin: .zero, size: Self.size)
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -10_000, y: -10_000), size: Self.size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = hosting
        window.orderFront(nil)
        defer { window.close() }
        for _ in 0..<20 {
            hosting.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(20))
        }
        let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)!
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        return rep
    }

    /// How red the title's strokes are: among the darkest pixels in the band below the cover
    /// (the title's cores, not its antialiased edges or the cover's wash behind), the average
    /// of red over the other channels.
    private func titleRedness(_ rep: NSBitmapImageRep) -> CGFloat {
        let scale = CGFloat(rep.pixelsWide) / Self.size.width
        var pixels: [(luma: CGFloat, red: CGFloat)] = []
        // The cover is 140pt tall under the 52pt header bar; the title is the next line down.
        for y in stride(from: 200.0, to: 260.0, by: 0.5) {
            for x in stride(from: 40.0, to: Self.size.width - 40, by: 0.5) {
                guard let c = rep.colorAt(x: Int(x * scale), y: Int(y * scale))?.usingColorSpace(.sRGB) else { continue }
                let luma = 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent
                pixels.append((luma, c.redComponent - max(c.greenComponent, c.blueComponent)))
            }
        }
        let darkest = pixels.sorted { $0.luma < $1.luma }.prefix(40)
        guard !darkest.isEmpty, darkest.last!.luma < 0.5 else { return -1 }
        return darkest.map(\.red).reduce(0, +) / CGFloat(darkest.count)
    }

    @Test func onlyTheAlbumTitleTakesTheCoversColour() async throws {
        let album = titleRedness(await render(.album))
        let playlist = titleRedness(await render(.playlist))
        #expect(album >= 0 && playlist >= 0, "the title should draw on both pages (album \(album), playlist \(playlist))")
        // The playlist's black title still picks up a trace of the red wash behind it.
        #expect(playlist < 0.08, "a playlist's title should stay the plain label, got redness \(playlist)")
        #expect(album > playlist + 0.12, "an album's title should take the cover's red, got redness \(album) against \(playlist)")
    }
}
