import AppKit
import SwiftUI
import Testing
@testable import Lilt

/// Where the cover's rim sits on the album hero's glass. The native Liquid Glass of the header
/// controls draws its own edge, and in dark mode that edge is two lines: a dark one in the half
/// point just outside the outline and the lit specular highlight in the point just inside it
/// (measured from Matt's frames of a red album page on Glass, at 2x: the dark line one pixel
/// outside the 76-pixel body on each side, the highlight peaking in the first pixel inside the
/// top and the bottom). A rim stroked outside the outline lands on the dark line, with the dark
/// showing between it and the body, and reads as offset; it belongs on the highlight. In light
/// mode the rim just outside the outline blends with the glass's lit edge, so it stays there.
///
/// The test host can't draw the native glass (`.glassEffect` and `NSGlassEffectView` come out
/// as the bare backdrop in `cacheDisplay`), so this measures the cast's own pixels against the
/// outline: the rows down through the top of the button, with the cast and without, and the
/// row where the cast's tint peaks, which is the rim (the wash fades from the top inward).
@MainActor
struct HeroGlassRimPositionRenderTests {
    static let red = Color(red: 0.85, green: 0.1, blue: 0.1)
    static let diameter = BrowseScreen.heroControlHeight
    static let margin: CGFloat = 10
    static let size = CGSize(width: diameter + 2 * margin, height: diameter + 2 * margin)
    /// The native glass's lit highlight in dark mode: the first point inside the outline.
    static let darkHighlight: Range<Double> = 0..<1
    /// Where the rim has sat in light mode: the point just outside the outline.
    static let lightRim: Range<Double> = -1..<0
    /// Less than this much tint (sRGB, largest channel) is no cast at all.
    static let untinted = 0.02

    static func palette(_ scheme: ColorScheme) -> CoverPalette {
        let cell = SurfaceMatrix.defaults[.glass, scheme]
        return CoverPalette(accent: red, cast: red, colorScheme: scheme, surface: .page, style: .standard, container: .standard, washOpacity: cell.platter.washOpacity, ground: cell.palette)
    }

    private func render(_ content: some View, _ scheme: ColorScheme) async -> NSBitmapImageRep {
        let size = Self.size
        let view = content
            .frame(width: size.width, height: size.height)
            .background(Color(.sRGB, white: scheme == .dark ? 0.2 : 0.9))
            .environment(\.colorScheme, scheme)
            .environment(\.appearsActive, true)
        let hosting = NSHostingView(rootView: AnyView(view))
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -10_000, y: -10_000), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
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

    private func button(_ modifier: some ViewModifier) -> some View {
        Color.clear
            .frame(width: Self.diameter, height: Self.diameter)
            .modifier(modifier)
    }

    /// The cast's tint, row by row down the top of the button's middle: each row's depth in
    /// points from the outline (negative outside), and how far the cast moved it from the plain
    /// surface.
    private func profile(_ scheme: ColorScheme) async -> [(depth: Double, tint: Double)] {
        let plain = await render(button(HeaderControlSurface(shape: Circle(), cornerRadius: Self.diameter / 2, tint: nil)), scheme)
        let cast = await render(button(HeroGlass(shape: Circle(), palette: Self.palette(scheme))), scheme)
        let scale = Double(cast.pixelsWide) / Self.size.width
        let x = Int(Self.size.width / 2 * scale)
        var rows: [(depth: Double, tint: Double)] = []
        for py in Int((Self.margin - 3) * scale)..<Int((Self.margin + 4) * scale) {
            let a = plain.colorAt(x: x, y: py)!, b = cast.colorAt(x: x, y: py)!
            let tint = max(abs(a.redComponent - b.redComponent), abs(a.greenComponent - b.greenComponent), abs(a.blueComponent - b.blueComponent))
            rows.append((Double(py) / scale - Self.margin, Double(tint)))
        }
        return rows
    }

    private static func describe(_ rows: [(depth: Double, tint: Double)]) -> String {
        rows.map { String(format: "%+.1f:%.3f", $0.depth, $0.tint) }.joined(separator: " ")
    }

    @Test func darkRimSitsOnTheGlassHighlight() async throws {
        let rows = await profile(.dark)
        print("HeroGlassRimPosition dark \(Self.describe(rows))")
        let peak = try #require(rows.max { $0.tint < $1.tint })
        #expect(Self.darkHighlight.contains(peak.depth), "the rim peaks \(peak.depth)pt from the outline, not on the highlight \(Self.darkHighlight): \(Self.describe(rows))")
        // Nothing of the cast falls outside the outline, on the glass's dark edge.
        let outside = rows.filter { $0.depth < 0 }.map(\.tint).max() ?? 0
        #expect(outside < Self.untinted, "tint \(outside) outside the outline: \(Self.describe(rows))")
    }

    @Test func lightRimStaysJustOutsideTheOutline() async throws {
        let rows = await profile(.light)
        print("HeroGlassRimPosition light \(Self.describe(rows))")
        let peak = try #require(rows.max { $0.tint < $1.tint })
        #expect(Self.lightRim.contains(peak.depth), "the light rim peaks \(peak.depth)pt from the outline: \(Self.describe(rows))")
    }
}
