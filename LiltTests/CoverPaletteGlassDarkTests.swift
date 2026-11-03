import AppKit
import SwiftUI
import Testing
@testable import Lilt

/// On the Glass window style in dark mode the panel is not the near-black the dark palette was
/// tuned on: it is what's behind the window, blurred and darkened a little, and over a light
/// desktop it comes out a mid grey (sRGB 0.45–0.5 in Matt's screenshot of a red album page).
/// The palette's lines must stay readable there, measured on a 0.5 grey, the light end of that
/// range.
///
/// The floors:
/// - Secondary (the artist line under the title and under each track) ≥ 3:1: WCAG's floor for
///   large text and for the parts of an interface you must see, and the one the contrast guard
///   already keeps the secondary lines to on the dark panel.
/// - Tertiary (the "Album • 1998" meta line, the track durations, the platter's times) ≥ 2.2:1:
///   no WCAG level covers the faintest line, so it is held to what the system's own tertiary
///   label (white at 25% in dark mode) reaches on the dark panel it was drawn for, 0.20 grey:
///   2.2:1. The faintest line on glass shouldn't read fainter than the faintest line on Normal.
/// - Dim controls (shuffle and repeat while off) ≥ 2.2:1 too: an inactive control is exempt
///   from WCAG's 3:1, but must still be found.
///
/// The ladder keeps its order (title brightest, tertiary below secondary) and its colour: each
/// dim line keeps the cover's hue within 12° and C ≥ 0.03, a tint and not grey.
@MainActor
struct CoverPaletteGlassDarkTests {
    /// The light end of what Glass shows over a light desktop.
    static let backdrop = 0.5
    static let secondaryFloor = 3.0
    static let tertiaryFloor = 2.2

    /// WCAG contrast of `color`, composited over the mid-grey glass, against it.
    static func contrast(_ color: Color) -> Double {
        let (r, g, b, a) = CoverPaletteDarkTests.rgb(color)
        let ground = backdrop
        func over(_ v: Double) -> Double { v * a + ground * (1 - a) }
        let fore = CoverPalette.luminance(over(r), over(g), over(b))
        let back = CoverPalette.luminance(ground, ground, ground)
        return (max(fore, back) + 0.05) / (min(fore, back) + 0.05)
    }

    static func lch(_ color: Color) -> CoverPaletteDarkTests.LCH {
        let (r, g, b, a) = CoverPaletteDarkTests.rgb(color)
        func over(_ v: Double) -> Double { v * a + backdrop * (1 - a) }
        return CoverPaletteDarkTests.oklch(over(r), over(g), over(b))
    }

    static func palette(_ seed: Color, _ surface: CoverPalette.Surface, _ windowStyle: Lilt.WindowStyle) -> CoverPalette {
        CoverPalette(accent: seed, cast: seed, colorScheme: .dark, surface: surface, windowStyle: windowStyle)
    }

    static func f(_ x: Double) -> String { String(format: "%.2f", x) }

    /// The 2.2:1 is the system's tertiary label on the dark panel; check the arithmetic.
    @Test func theTertiaryFloorIsTheSystemsTertiaryLabelOnTheDarkPanel() {
        let ground = CoverPalette.panelBackground(.dark)
        let shown = 1 * 0.25 + ground * 0.75
        let ratio = (CoverPalette.luminance(shown, shown, shown) + 0.05) / (CoverPalette.luminance(ground, ground, ground) + 0.05)
        #expect(abs(ratio - Self.tertiaryFloor) < 0.05, "system tertiary on the dark panel: \(Self.f(ratio))")
    }

    /// An album page on Glass in dark mode: the artist lines, the meta line, the durations and
    /// the dim controls stay readable on a mid-grey backdrop, in order and in the cover's hue.
    @Test func pageLinesReadOnMidGreyGlass() throws {
        for (name, seed) in CoverPaletteDarkTests.seeds.sorted(by: { $0.key < $1.key }) {
            let (r, g, b, _) = CoverPaletteDarkTests.rgb(seed)
            let accent = CoverPaletteDarkTests.oklch(r, g, b)
            let p = Self.palette(seed, .page, .glass)
            let title = try #require(p.primary)
            let secondary = try #require(p.secondary)
            let tertiary = try #require(p.tertiary)
            let dim = try #require(p.dimControl)
            #expect(Self.contrast(secondary) >= Self.secondaryFloor, "\(name) secondary \(Self.f(Self.contrast(secondary))):1 on glass")
            #expect(Self.contrast(tertiary) >= Self.tertiaryFloor, "\(name) tertiary \(Self.f(Self.contrast(tertiary))):1 on glass")
            #expect(Self.contrast(dim) >= Self.tertiaryFloor, "\(name) dimControl \(Self.f(Self.contrast(dim))):1 on glass")
            let t = Self.lch(title), s = Self.lch(secondary), te = Self.lch(tertiary)
            #expect(s.l < t.l, "\(name) secondary L\(Self.f(s.l)) should sit below the title L\(Self.f(t.l))")
            #expect(te.l < s.l, "\(name) tertiary L\(Self.f(te.l)) should sit below secondary L\(Self.f(s.l))")
            for (role, x) in [("secondary", s), ("tertiary", te)] {
                #expect(x.c >= 0.03, "\(name) \(role) too grey: C\(x.c)")
                #expect(CoverPaletteDarkTests.hueDistance(x.h, accent.h) <= 12, "\(name) \(role) off hue")
            }
        }
    }

    /// The platter's times, elapsed and total, wear its tertiary role; on Glass the platter
    /// sits on the same backdrop.
    @Test func platterTimesReadOnMidGreyGlass() throws {
        for (name, seed) in CoverPaletteDarkTests.seeds.sorted(by: { $0.key < $1.key }) {
            let p = Self.palette(seed, .platter, .glass)
            let times = try #require(p.tertiary)
            #expect(Self.contrast(times) >= Self.tertiaryFloor, "\(name) platter times \(Self.f(Self.contrast(times))):1 on glass")
            let secondary = try #require(p.secondary)
            #expect(Self.contrast(secondary) >= Self.secondaryFloor, "\(name) platter artist \(Self.f(Self.contrast(secondary))):1 on glass")
        }
    }

    /// Normal and Solid sit on the sidebar material, near-black in dark mode: they keep the
    /// ladder `CoverPaletteDarkTests` checks, colour for colour.
    @Test func normalAndSolidKeepTheDarkPanelLadder() throws {
        for (name, seed) in CoverPaletteDarkTests.seeds {
            let reference = CoverPaletteDarkTests.palette(seed, .page)
            for style in [Lilt.WindowStyle.normal, .solid] {
                let p = Self.palette(seed, .page, style)
                for path in [\CoverPalette.primary, \.control, \.secondary, \.tertiary, \.dimControl] {
                    #expect(p[keyPath: path] == reference[keyPath: path], "\(name) \(style) changed")
                }
            }
        }
    }
}
