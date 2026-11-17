import AppKit
import SwiftUI
import Testing
@testable import Lilt

/// The ambience drawer sits under the platter's scrubber, so its levels wear the scrubber's
/// line colour (the platter's control colour), not the cover's raw accent.
@MainActor
struct AmbienceColorTests {
    /// A saturated red, like the cover in the report: its raw accent is plainly brighter than
    /// the control colour the platter mixes from it.
    private static let accent = Color(.sRGB, red: 0.85, green: 0.1, blue: 0.1)

    private func sliderCells(in view: NSView) -> [LineSliderCell] {
        let own = (view as? NSSlider)?.cell as? LineSliderCell
        return (own.map { [$0] } ?? []) + view.subviews.flatMap(sliderCells)
    }

    private func components(_ color: NSColor?) -> [CGFloat]? {
        guard let c = color?.usingColorSpace(.sRGB) else { return nil }
        return [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent]
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func levelsWearTheScrubbersLine(_ scheme: ColorScheme) async throws {
        let size = CGSize(width: 300, height: AmbiencePanel.height)
        let view = AmbiencePanel(accent: Self.accent)
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, scheme)
            .environment(AmbienceService())
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -10_000, y: -10_000), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        for _ in 0..<5 { try? await Task.sleep(for: .milliseconds(20)) }

        let cells = sliderCells(in: hosting)
        try #require(cells.count == 2, "the drawer should have two levels; found \(cells.count)")

        // What the platter's playhead wears (NowPlayingBar's scrubber line).
        let platter = ArtworkStyle.shared.platter
        let palette = CoverPalette(accent: Self.accent, colorScheme: scheme, surface: .platter, windowStyle: ArtworkStyle.shared.shownWindowStyle(reduceTransparency: false))
        let line = platter.scrubberLikeControls ? palette.control : palette.mono.mix(with: Self.accent, by: platter.scrubberTint)
        let expected = try #require(components(line.map { NSColor($0) }))

        for cell in cells {
            let got = try #require(components(cell.tint), "a level has no tint")
            let off = zip(got, expected).map { abs($0 - $1) }.max() ?? 1
            #expect(off < 0.01, "a level wears \(got), the scrubber's line \(expected) (\(scheme))")
        }
    }
}
