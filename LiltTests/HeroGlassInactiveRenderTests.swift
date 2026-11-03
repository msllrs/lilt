import AppKit
import SwiftUI
import Testing
@testable import Lilt

/// The album hero's Save, Play and Shuffle glass, rendered off-screen with a red cover's cast:
/// while the window is active the cover's wash and rim light the top of the button; while it
/// isn't, the button is the plain header-control surface, as the rest of an inactive window is,
/// with no cover colour on it.
@MainActor
struct HeroGlassInactiveRenderTests {
    static let backdrop = CoverPaletteGlassDarkTests.backdrop
    static let red = Color(red: 0.85, green: 0.1, blue: 0.1)
    static let size = CGSize(width: BrowseScreen.heroControlHeight + 20, height: BrowseScreen.heroControlHeight + 20)

    private func render(_ content: some View) async -> NSBitmapImageRep {
        let size = Self.size
        let view = content
            .frame(width: size.width, height: size.height)
            .background(Color(.sRGB, white: Self.backdrop))
            .environment(\.colorScheme, .dark)
        let hosting = NSHostingView(rootView: AnyView(view))
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -10_000, y: -10_000), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.colorSpace = .sRGB
        window.contentView = hosting
        window.orderFront(nil)
        defer { window.close() }
        for _ in 0..<10 {
            hosting.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(20))
        }
        let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)!
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        return rep
    }

    /// A bare button: an empty circle of the hero control's size.
    private func button(_ modifier: some ViewModifier) -> some View {
        Color.clear
            .frame(width: BrowseScreen.heroControlHeight, height: BrowseScreen.heroControlHeight)
            .modifier(modifier)
    }

    /// The average sRGB of the button's top band, where the wash is strongest and the rim runs:
    /// the top fifth of the circle, across its middle third.
    private func topBand(_ rep: NSBitmapImageRep) -> (r: Double, g: Double, b: Double) {
        let scale = Double(rep.pixelsWide) / Self.size.width
        let d = Double(BrowseScreen.heroControlHeight)
        let left = (Self.size.width - d) / 2, top = (Self.size.height - d) / 2
        var sum = (r: 0.0, g: 0.0, b: 0.0), n = 0.0
        for py in stride(from: top, to: top + d / 5, by: 0.5) {
            for px in stride(from: left + d / 3, to: left + 2 * d / 3, by: 0.5) {
                guard let c = rep.colorAt(x: Int(px * scale), y: Int(py * scale)) else { continue }
                sum.r += Double(c.redComponent); sum.g += Double(c.greenComponent); sum.b += Double(c.blueComponent)
                n += 1
            }
        }
        return (sum.r / n, sum.g / n, sum.b / n)
    }

    private static func distance(_ a: (r: Double, g: Double, b: Double), _ b: (r: Double, g: Double, b: Double)) -> Double {
        max(abs(a.r - b.r), abs(a.g - b.g), abs(a.b - b.b))
    }

    @Test func inactiveWindowDropsTheCoverCast() async throws {
        let palette = CoverPaletteGlassDarkTests.palette(Self.red, .page, .glass).casting(Self.red)
        try #require(palette.containerWash != nil && palette.containerRim != nil, "the red cover casts no wash")

        let plain = topBand(await render(button(HeaderControlSurface(shape: Circle(), cornerRadius: BrowseScreen.heroControlHeight / 2, tint: nil))))
        let active = topBand(await render(button(HeroGlass(shape: Circle(), palette: palette)).environment(\.appearsActive, true)))
        let inactive = topBand(await render(button(HeroGlass(shape: Circle(), palette: palette)).environment(\.appearsActive, false)))

        let f = { (c: (r: Double, g: Double, b: Double)) in String(format: "(%.3f, %.3f, %.3f)", c.r, c.g, c.b) }
        print("HeroGlassInactiveRender plain \(f(plain)) active \(f(active)) inactive \(f(inactive))")
        // Active: the cover's red lights the top of the button.
        #expect(Self.distance(active, plain) > 0.03, "active \(f(active)) against plain \(f(plain))")
        #expect(active.r - active.b > plain.r - plain.b + 0.02, "active top not tinted red: \(f(active))")
        // Inactive: the plain surface, no wash or rim.
        #expect(Self.distance(inactive, plain) < 0.01, "inactive \(f(inactive)) against plain \(f(plain))")
    }
}
