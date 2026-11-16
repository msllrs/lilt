import AppKit
import SwiftUI
import Testing
@testable import Lilt

/// The header's blur covers the glass window's rim, so `HeaderBackdrop` draws the rim back on
/// top: the window's rounded outline, lit along the top and fading to a dark line at its bottom.
/// Only the top of that outline belongs there. Under a header as tall as a library shelf's (its
/// title and the filter field) the outline's bottom edge, a dark curved line, showed across the
/// panel just under the field once the list scrolled.
///
/// This renders the backdrop under headers of each height and looks down the middle of the
/// panel, below the lit top, for anything darker than the surface it sits on.
@MainActor
struct HeaderBackdropRimTests {
    static let width: CGFloat = 320
    static let below: CGFloat = 160
    /// The panel under the header, in each appearance.
    static func ground(_ scheme: ColorScheme) -> Double { scheme == .dark ? 0.2 : 0.9 }
    /// The top few points are the lit rim itself.
    static let topRim: CGFloat = 4
    /// Darker than the panel by more than this is a line: the rim's dark bottom is faint, about
    /// a hundredth darker on light glass.
    static let tolerance = 0.004

    private func render(header: CGFloat, _ scheme: ColorScheme) async -> NSBitmapImageRep {
        let size = CGSize(width: Self.width, height: header + Self.below)
        let view = VStack(spacing: 0) {
            Color.clear.frame(height: header).headerBackdrop(visibility: 1)
            Spacer(minLength: 0)
        }
        .frame(width: size.width, height: size.height)
        .background(Color(.sRGB, white: Self.ground(scheme)))
        .environment(\.colorScheme, scheme)
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

    @Test(arguments: [ColorScheme.light, .dark])
    func noRimLineCrossesThePanelUnderATallHeader(_ scheme: ColorScheme) async throws {
        // The rim is only drawn back on the glass surface, with the backdrop blur.
        try #require(ArtworkStyle.shared.headerBlur.useBackdrop && ProgressiveBlurBackdrop.isAvailable, "the backdrop blur is off here")
        try #require(ArtworkStyle.shared.panel.effective(reduceTransparency: false).surface == .glass, "the panel isn't on Glass here")

        // Library's and Search's headers, up through a shelf's and taller.
        for header in stride(from: CGFloat(56), through: 160, by: 8) {
            let rep = await render(header: header, scheme)
            let scale = Double(rep.pixelsWide) / Self.width
            let x = rep.pixelsWide / 2
            // The panel as drawn, from the bottom row, well below the backdrop's reach.
            let ground = Double(rep.colorAt(x: x, y: rep.pixelsHigh - 1)!.usingColorSpace(.sRGB)!.brightnessComponent)
            var darkest = (y: 0.0, white: 1.0)
            for py in Int(Self.topRim * scale)..<rep.pixelsHigh {
                let white = Double(rep.colorAt(x: x, y: py)!.usingColorSpace(.sRGB)!.brightnessComponent)
                if white < darkest.white { darkest = (Double(py) / scale, white) }
            }
            #expect(darkest.white >= ground - Self.tolerance, "a \(Int(header))pt header has a line \(String(format: "%.3f", ground - darkest.white)) darker than the panel at \(String(format: "%.1f", darkest.y))pt")
        }
    }
}
