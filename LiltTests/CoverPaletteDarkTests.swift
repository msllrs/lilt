import AppKit
import SwiftUI
import Testing
@testable import Lilt

/// In dark mode the cover's colour must read as a clear, light tint of its hue, the way coloured
/// text sits on a dark background in Apple Music, rather than a muddy grey-blue that is neither
/// white nor a colour. These check the roles by their OKLCH coordinates, worked out here from
/// the resolved sRGB so the check doesn't lean on the palette's own maths.
///
/// The thresholds:
/// - Lightness ≥ 0.80 for the title and the controls. OKLab L 0.8 is about Y 0.5, roughly 6.5:1
///   on the guard's 0.20 grey panel, so the line reads as light text, not a mid-tone. The muddy
///   roles sat at 0.70–0.79.
/// - Chroma ≥ 0.05. About two and a half just-noticeable differences (ΔE_ok ≈ 0.02) away from
///   grey: a tint you see as a colour at a glance. It is also what sRGB still allows for blue at
///   the title's lightness (about 0.058 at L 0.88), so the bound asks for the hue, not for neon.
/// - Hue within 12° of the accent's, so the tint is the cover's colour and not a neighbour.
/// - Chroma no more than 0.14, so the lighter roles stay a tint and never go neon.
@MainActor
struct CoverPaletteDarkTests {
    /// Saturated covers, as solid colours: the ones the muddy mix hit hardest.
    static let seeds: [String: Color] = [
        "blue": Color(red: 0.1, green: 0.2, blue: 0.95),
        "navy": Color(red: 0.1, green: 0.2, blue: 0.45),
        "orange": Color(red: 0.95, green: 0.5, blue: 0.1),
        "red": Color(red: 0.85, green: 0.1, blue: 0.1),
        "teal": Color(red: 0.1, green: 0.6, blue: 0.6),
        "purple": Color(red: 0.5, green: 0.15, blue: 0.75),
    ]

    struct LCH { var l, c, h: Double }

    /// OKLCH of a gamma-encoded sRGB colour (Björn Ottosson's OKLab).
    static func oklch(_ r: Double, _ g: Double, _ b: Double) -> LCH {
        func linear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        let (lr, lg, lb) = (linear(r), linear(g), linear(b))
        let l = cbrt(0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb)
        let m = cbrt(0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb)
        let s = cbrt(0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb)
        let L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
        let a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        let bb = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        var h = atan2(bb, a) * 180 / .pi
        if h < 0 { h += 360 }
        return LCH(l: L, c: hypot(a, bb), h: h)
    }

    static func rgb(_ color: Color) -> (Double, Double, Double, Double) {
        var environment = EnvironmentValues()
        environment.colorScheme = .dark
        let c = color.resolve(in: environment)
        return (Double(c.red), Double(c.green), Double(c.blue), Double(c.opacity))
    }

    /// A colour as it shows on the guard's dark panel: composited over the 0.20 grey.
    static func shown(_ color: Color) -> LCH {
        let (r, g, b, a) = rgb(color)
        let ground = CoverPalette.panelBackground(.dark)
        func over(_ v: Double) -> Double { v * a + ground * (1 - a) }
        return oklch(over(r), over(g), over(b))
    }

    /// A cast added as light (plus-lighter) to dark glass, standing in for the glass with the
    /// panel's grey.
    static func added(_ color: Color) -> LCH {
        let (r, g, b, a) = rgb(color)
        let ground = CoverPalette.panelBackground(.dark)
        func plus(_ v: Double) -> Double { min(1, ground + v * a) }
        return oklch(plus(r), plus(g), plus(b))
    }

    static func hueDistance(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(d, 360 - d)
    }

    static func palette(_ seed: Color, _ surface: CoverPalette.Surface) -> CoverPalette {
        CoverPalette(accent: seed, cast: seed, colorScheme: .dark, surface: surface, style: .standard, container: .standard, washOpacity: 0.32)
    }

    /// The title and the controls (glyphs, Play's label, the scrubber) on a page and on the
    /// platter: light, and clearly the cover's hue.
    @Test func titleAndControlsAreAClearLightTintOfTheCover() throws {
        for (name, seed) in Self.seeds.sorted(by: { $0.key < $1.key }) {
            let (r, g, b, _) = Self.rgb(seed)
            let accent = Self.oklch(r, g, b)
            for surface in [CoverPalette.Surface.page, .platter] {
                let p = Self.palette(seed, surface)
                for (role, path) in [("primary", \CoverPalette.primary), ("control", \CoverPalette.control)] {
                    let color = try #require(p[keyPath: path])
                    let lch = Self.shown(color)
                    let label = "\(name) \(surface) \(role) L\(String(format: "%.3f", lch.l)) C\(String(format: "%.3f", lch.c)) h\(String(format: "%.0f", lch.h))"
                    #expect(lch.l >= 0.80, "too dark to read as light text: \(label)")
                    #expect(lch.c >= 0.05, "too grey to read as the cover's colour: \(label)")
                    #expect(lch.c <= 0.14, "too vivid for text: \(label)")
                    #expect(Self.hueDistance(lch.h, accent.h) <= 12, "drifted off the cover's hue (\(String(format: "%.0f", accent.h))): \(label)")
                }
            }
        }
    }

    /// The dimmer roles keep the hue too, and step down in lightness below the title.
    @Test func dimmerRolesKeepTheHueAndStepDown() throws {
        for (name, seed) in Self.seeds.sorted(by: { $0.key < $1.key }) {
            let (r, g, b, _) = Self.rgb(seed)
            let accent = Self.oklch(r, g, b)
            let p = Self.palette(seed, .page)
            let title = Self.shown(try #require(p.primary))
            for (role, path) in [("secondary", \CoverPalette.secondary), ("tertiary", \CoverPalette.tertiary), ("dimControl", \CoverPalette.dimControl)] {
                let lch = Self.shown(try #require(p[keyPath: path]))
                let label = "\(name) \(role) L\(String(format: "%.3f", lch.l)) C\(String(format: "%.3f", lch.c)) h\(String(format: "%.0f", lch.h))"
                #expect(lch.l < title.l, "should sit below the title: \(label)")
                #expect(lch.c >= 0.05, "too grey: \(label)")
                #expect(Self.hueDistance(lch.h, accent.h) <= 12, "off hue: \(label)")
            }
        }
    }

    /// The contrast guard still holds every line to its floor on the dark panel.
    @Test func everyRoleKeepsItsContrastFloor() throws {
        for (name, seed) in Self.seeds {
            let p = Self.palette(seed, .page)
            #expect(p.contrast(try #require(p.primary)) >= CoverPalette.primaryFloor, "\(name) primary")
            #expect(p.contrast(try #require(p.control)) >= CoverPalette.primaryFloor, "\(name) control")
            #expect(p.contrast(try #require(p.secondary)) >= CoverPalette.secondaryFloor, "\(name) secondary")
            #expect(p.contrast(try #require(p.dimControl)) >= CoverPalette.secondaryFloor, "\(name) dimControl")
        }
    }

    /// The cast on the glass controls (the Play capsule, the hero's round buttons, the back
    /// button, the platter's edge): a light, clear colour of the cover's hue, so that added as
    /// light to dark glass the rim reads as lit colour and the wash as a glow, not a grey stain.
    ///
    /// - The container itself at L ≥ 0.70 and C ≥ 0.09: plus-lighter adds the colour's own
    ///   light, so a dim cast adds next to nothing and a pale one adds only white.
    /// - The rim as it shows (added to the 0.20 grey) at L ≥ 0.50 and C ≥ 0.045; the wash, which
    ///   is meant to be faint, at C ≥ 0.028. The muddy rims sat at L 0.39–0.44.
    /// - Both within 15° of the cover's hue (adding light to grey pulls the hue a little).
    @Test func theCastOnGlassIsALitColourOfTheCover() throws {
        for (name, seed) in Self.seeds.sorted(by: { $0.key < $1.key }) {
            let (r, g, b, _) = Self.rgb(seed)
            let accent = Self.oklch(r, g, b)
            let p = Self.palette(seed, .page)
            let fill = Self.shown(try #require(p.accentContainer))
            let rim = Self.added(try #require(p.containerRim))
            let wash = Self.added(try #require(p.containerWash))
            func f(_ x: LCH) -> String { "L\(String(format: "%.3f", x.l)) C\(String(format: "%.3f", x.c)) h\(String(format: "%.0f", x.h))" }
            #expect(fill.l >= 0.70 && fill.c >= 0.09, "\(name) container \(f(fill))")
            #expect(Self.hueDistance(fill.h, accent.h) <= 12, "\(name) container off hue \(f(fill))")
            #expect(rim.l >= 0.50 && rim.c >= 0.045, "\(name) rim on dark glass \(f(rim))")
            #expect(Self.hueDistance(rim.h, accent.h) <= 15, "\(name) rim off hue \(f(rim))")
            #expect(wash.c >= 0.028, "\(name) wash on dark glass \(f(wash))")
            #expect(Self.hueDistance(wash.h, accent.h) <= 15, "\(name) wash off hue \(f(wash))")
            #expect(p.containerBlend == .plusLighter)
        }
    }

    /// A cover with hardly any colour stays nearly neutral: the palette doesn't invent a hue.
    @Test func aGreyishCoverStaysNearlyNeutral() throws {
        let sand = Color(red: 0.9, green: 0.85, blue: 0.7)
        let p = Self.palette(sand, .page)
        let (r, g, b, _) = Self.rgb(sand)
        let accent = Self.oklch(r, g, b)
        for path in [\CoverPalette.primary, \.control, \.secondary, \.accentContainer] {
            let lch = Self.shown(try #require(p[keyPath: path]))
            #expect(lch.c <= accent.c + 0.01, "sand gained colour: C\(lch.c) over \(accent.c)")
        }
    }
}
