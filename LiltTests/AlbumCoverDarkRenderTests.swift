import AppKit
import SwiftUI
import Testing
@testable import Lilt

/// An album page in dark mode, rendered off-screen: its title and the ⋯ glyph should come out a
/// light, clear tint of the cover's hue, not the grey-blue the linear mix with white gave.
/// Samples the cores of the strokes (the brightest pixels in each region) and reads them in
/// OKLCH with `CoverPaletteDarkTests`' converter.
@MainActor
struct AlbumCoverDarkRenderTests {
    private static let size = CGSize(width: 320, height: 420)

    static let covers: [(name: String, rgb: (CGFloat, CGFloat, CGFloat))] = [
        ("blue", (0.12, 0.32, 0.78)),
        ("orange", (0.95, 0.5, 0.1)),
    ]

    private static func coverURL(_ name: String, _ rgb: (CGFloat, CGFloat, CGFloat)) -> URL {
        let url = URL(string: "https://lh3.googleusercontent.com/test-album-dark-\(name)=w544-h544-l90-rj")!
        if ImageCache.shared.cached(url) == nil {
            let image = NSImage(size: NSSize(width: 120, height: 120), flipped: false) { rect in
                NSColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1).setFill()
                rect.fill()
                return true
            }
            ImageCache.shared.store(image, for: url)
        }
        return url
    }

    private func render(_ name: String, _ rgb: (CGFloat, CGFloat, CGFloat)) async -> NSBitmapImageRep {
        let saved = UserDefaults.standard.data(forKey: "navigationState")
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: "navigationState") } else { UserDefaults.standard.removeObject(forKey: "navigationState") }
        }
        let auth = AuthService()
        let music = YTMusicClient(auth: auth, fetchPage: { _ in JSONObject(value: [:]) })
        let item = BrowseItem(id: "cover-dark-\(name)", kind: .album, title: "WWWWWWWW", subtitle: "", artworkURL: Self.coverURL(name, rgb))
        let navigation = NavigationModel()
        navigation.path = [item]
        let ground = CoverPalette.panelBackground(.dark)
        let view = BrowseScreen(item: item)
            .frame(width: Self.size.width, height: Self.size.height)
            .background(Color(white: ground))
            .environment(\.colorScheme, .dark)
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
        window.appearance = NSAppearance(named: .darkAqua)
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

    /// The average of the brightest pixels in a region (in points): the cores of light strokes.
    private func strokeCore(_ rep: NSBitmapImageRep, x: ClosedRange<Double>, y: ClosedRange<Double>, count: Int = 30) -> CoverPaletteDarkTests.LCH? {
        let scale = Double(rep.pixelsWide) / Self.size.width
        var pixels: [(luma: Double, r: Double, g: Double, b: Double)] = []
        for py in stride(from: y.lowerBound, to: y.upperBound, by: 0.5) {
            for px in stride(from: x.lowerBound, to: x.upperBound, by: 0.5) {
                guard let c = rep.colorAt(x: Int(px * scale), y: Int(py * scale))?.usingColorSpace(.sRGB) else { continue }
                let (r, g, b) = (Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent))
                pixels.append((0.2126 * r + 0.7152 * g + 0.0722 * b, r, g, b))
            }
        }
        let top = pixels.sorted { $0.luma > $1.luma }.prefix(count)
        guard !top.isEmpty else { return nil }
        let n = Double(top.count)
        return CoverPaletteDarkTests.oklch(top.map(\.r).reduce(0, +) / n, top.map(\.g).reduce(0, +) / n, top.map(\.b).reduce(0, +) / n)
    }

    private static func f(_ x: CoverPaletteDarkTests.LCH) -> String {
        String(format: "L%.3f C%.3f h%.0f", x.l, x.c, x.h)
    }

    @Test func darkAlbumTitleAndGlyphAreALightClearTint() async throws {
        for cover in Self.covers {
            let rep = await render(cover.name, cover.rgb)
            let accent = CoverPaletteDarkTests.oklch(Double(cover.rgb.0), Double(cover.rgb.1), Double(cover.rgb.2))
            // The title is the line under the 140pt cover; the ⋯ sits at the header's trailing end.
            let title = try #require(strokeCore(rep, x: 40...280, y: 200...260))
            let glyph = try #require(strokeCore(rep, x: 270...316, y: 4...60, count: 12))
            print("AlbumCoverDarkRender \(cover.name) cover \(Self.f(accent)) title \(Self.f(title)) glyph \(Self.f(glyph))")
            for (role, lch) in [("title", title), ("glyph", glyph)] {
                #expect(lch.l >= 0.78, "\(cover.name) \(role) too dark: \(Self.f(lch))")
                #expect(lch.c >= 0.045, "\(cover.name) \(role) too grey: \(Self.f(lch))")
                #expect(CoverPaletteDarkTests.hueDistance(lch.h, accent.h) <= 20, "\(cover.name) \(role) off hue: \(Self.f(lch))")
            }
        }
    }
}
