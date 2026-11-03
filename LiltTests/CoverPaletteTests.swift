import AppKit
import SwiftUI
import Testing
@testable import Lilt

/// `CoverPalette` took over every surface's own mix of the cover's colour. These pin each role to
/// the colour it replaced, resolved, as captured from the code before the palette existed (the
/// platter's `CoverTint`, an album page's guarded tint and playing-row pill, the platter's corner
/// wash and scrubber line, and the cast the Play capsule and back button wear), so at the default
/// dials nothing on screen can change.
@MainActor
struct CoverPaletteTests {
    static let seeds: [String: Color] = [
        "red": Color(red: 0.85, green: 0.1, blue: 0.1),
        "navy": Color(red: 0.1, green: 0.2, blue: 0.45),
        "yellow": Color(red: 0.8, green: 0.8, blue: 0.0),
        "blue": Color(red: 0.1, green: 0.2, blue: 0.95),
        "sand": Color(red: 0.9, green: 0.85, blue: 0.7),
    ]

    /// (seed, scheme, surface.role, resolved sRGB + opacity) from the code before the palette.
    /// The yellow and sand pages in light mode are where the contrast guard lowered the controls'
    /// share. Light mode is pinned in full. In dark mode only the accent's own opacities (the
    /// platter's wash, a page's playing-row pill) are pinned: the dark content, control and
    /// container roles were muddy and are now derived in OKLCH, so they are checked by their
    /// properties in `CoverPaletteDarkTests` instead of by their old pixels.
    static let before: [(String, ColorScheme, String, [Float])] = [
        ("red", .light, "platter.primary", [0.23288804, 0.008287616, 0.008287682, 1.0]),
        ("red", .light, "platter.secondary", [0.17496842, 0.004833863, 0.00483394, 0.5984314]),
        ("red", .light, "platter.tertiary", [0.31727567, 0.0153592, 0.015359317, 0.40705884]),
        ("red", .light, "platter.control", [0.46305227, 0.033946298, 0.033946306, 1.0]),
        ("red", .light, "platter.dimControl", [0.6096206, 0.058829777, 0.058830127, 0.8192941]),
        ("red", .light, "platter.wash", [0.85, 0.09999999, 0.09999999, 0.32]),
        ("red", .light, "platter.scrubber", [0.46305227, 0.033946298, 0.033946306, 1.0]),
        ("red", .light, "page.primary", [0.23288804, 0.008287616, 0.008287682, 1.0]),
        ("red", .light, "page.secondary", [0.17496842, 0.004833863, 0.00483394, 0.5984314]),
        ("red", .light, "page.tertiary", [0.31727567, 0.0153592, 0.015359317, 0.40705884]),
        ("red", .light, "page.control", [0.46305227, 0.033946298, 0.033946306, 1.0]),
        ("red", .light, "page.dimControl", [0.6096206, 0.058829777, 0.058830127, 0.8192941]),
        ("red", .light, "page.highlight", [0.85, 0.09999999, 0.09999999, 0.12]),
        ("red", .light, "container.fill", [0.85, 0.09999999, 0.09999999, 1.0]),
        ("red", .light, "container.wash", [0.85, 0.09999999, 0.09999999, 0.2]),
        ("red", .light, "container.rim", [0.85, 0.09999999, 0.09999999, 0.24]),
        ("red", .dark, "platter.wash", [0.85, 0.09999999, 0.09999999, 0.32]),
        ("red", .dark, "page.highlight", [0.85, 0.09999999, 0.09999999, 0.16]),
        ("navy", .light, "platter.primary", [0.008287663, 0.027373673, 0.105644695, 1.0]),
        ("navy", .light, "platter.secondary", [0.0048338976, 0.015966147, 0.07332488, 0.5984314]),
        ("navy", .light, "platter.tertiary", [0.015359266, 0.04989534, 0.15273389, 0.40705884]),
        ("navy", .light, "platter.control", [0.033946227, 0.09097051, 0.2340788, 1.0]),
        ("navy", .light, "platter.dimControl", [0.058829837, 0.13226882, 0.31586555, 0.8192941]),
        ("navy", .light, "platter.wash", [0.09999999, 0.19999999, 0.45, 0.32]),
        ("navy", .light, "platter.scrubber", [0.033946227, 0.09097051, 0.2340788, 1.0]),
        ("navy", .light, "page.primary", [0.008287663, 0.027373673, 0.105644695, 1.0]),
        ("navy", .light, "page.secondary", [0.0048338976, 0.015966147, 0.07332488, 0.5984314]),
        ("navy", .light, "page.tertiary", [0.015359266, 0.04989534, 0.15273389, 0.40705884]),
        ("navy", .light, "page.control", [0.033946227, 0.09097051, 0.2340788, 1.0]),
        ("navy", .light, "page.dimControl", [0.058829837, 0.13226882, 0.31586555, 0.8192941]),
        ("navy", .light, "page.highlight", [0.09999999, 0.19999999, 0.45, 0.12]),
        ("navy", .light, "container.fill", [0.09999999, 0.19999999, 0.45, 1.0]),
        ("navy", .light, "container.wash", [0.09999999, 0.19999999, 0.45, 0.2]),
        ("navy", .light, "container.rim", [0.09999999, 0.19999999, 0.45, 0.24]),
        ("navy", .dark, "platter.wash", [0.09999999, 0.19999999, 0.45, 0.32]),
        ("navy", .dark, "page.highlight", [0.09999999, 0.19999999, 0.45, 0.16]),
        ("yellow", .light, "platter.primary", [0.2169826, 0.21698257, 0.0, 1.0]),
        ("yellow", .light, "platter.secondary", [0.16226292, 0.16226298, -4.813075e-08, 0.5984314]),
        ("yellow", .light, "platter.tertiary", [0.29670793, 0.29670793, -1.4439226e-07, 0.40705884]),
        ("yellow", .light, "platter.control", [0.4344303, 0.43443072, -2.8878452e-07, 1.0]),
        ("yellow", .light, "platter.dimControl", [0.57290107, 0.57290125, 0.0, 0.8192941]),
        ("yellow", .light, "platter.wash", [0.8, 0.8, 0.0, 0.32]),
        ("yellow", .light, "platter.scrubber", [0.4344303, 0.43443072, -2.8878452e-07, 1.0]),
        ("yellow", .light, "page.primary", [0.2169826, 0.21698257, 0.0, 1.0]),
        ("yellow", .light, "page.secondary", [0.16226292, 0.16226298, -4.813075e-08, 0.5984314]),
        ("yellow", .light, "page.tertiary", [0.29670793, 0.29670793, -1.4439226e-07, 0.40705884]),
        ("yellow", .light, "page.control", [0.41538724, 0.41538754, -1.92523e-07, 1.0]),
        ("yellow", .light, "page.dimControl", [0.35152885, 0.35152918, -2.8878452e-07, 0.6887843]),
        ("yellow", .light, "page.highlight", [0.8, 0.8, 0.0, 0.12]),
        ("yellow", .light, "container.fill", [0.8, 0.8, 0.0, 1.0]),
        ("yellow", .light, "container.wash", [0.8, 0.8, 0.0, 0.2]),
        ("yellow", .light, "container.rim", [0.8, 0.8, 0.0, 0.24]),
        ("yellow", .dark, "platter.wash", [0.8, 0.8, 0.0, 0.32]),
        ("yellow", .dark, "page.highlight", [0.8, 0.8, 0.0, 0.16]),
        ("blue", .light, "platter.primary", [0.008287694, 0.027373655, 0.26469883, 1.0]),
        ("blue", .light, "platter.secondary", [0.004833928, 0.015966138, 0.20037925, 0.5984314]),
        ("blue", .light, "platter.tertiary", [0.015359293, 0.049895324, 0.35841107, 0.40705884]),
        ("blue", .light, "platter.control", [0.033945993, 0.09097061, 0.52029556, 1.0]),
        ("blue", .light, "platter.dimControl", [0.05882983, 0.13226882, 0.6830593, 0.8192941]),
        ("blue", .light, "platter.wash", [0.09999999, 0.19999999, 0.95, 0.32]),
        ("blue", .light, "platter.scrubber", [0.033945993, 0.09097061, 0.52029556, 1.0]),
        ("blue", .light, "page.primary", [0.008287694, 0.027373655, 0.26469883, 1.0]),
        ("blue", .light, "page.secondary", [0.004833928, 0.015966138, 0.20037925, 0.5984314]),
        ("blue", .light, "page.tertiary", [0.015359293, 0.049895324, 0.35841107, 0.40705884]),
        ("blue", .light, "page.control", [0.033945993, 0.09097061, 0.52029556, 1.0]),
        ("blue", .light, "page.dimControl", [0.05882983, 0.13226882, 0.6830593, 0.8192941]),
        ("blue", .light, "page.highlight", [0.09999999, 0.19999999, 0.95, 0.12]),
        ("blue", .light, "container.fill", [0.09999999, 0.19999999, 0.95, 1.0]),
        ("blue", .light, "container.wash", [0.09999999, 0.19999999, 0.95, 0.2]),
        ("blue", .light, "container.rim", [0.09999999, 0.19999999, 0.95, 0.24]),
        ("blue", .dark, "platter.wash", [0.09999999, 0.19999999, 0.95, 0.32]),
        ("blue", .dark, "page.highlight", [0.09999999, 0.19999999, 0.95, 0.16]),
        ("sand", .light, "platter.primary", [0.24879342, 0.23288807, 0.18517175, 1.0]),
        ("sand", .light, "platter.secondary", [0.18767375, 0.17496845, 0.13685203, 0.5984314]),
        ("sand", .light, "platter.tertiary", [0.33784336, 0.3172757, 0.2555725, 0.40705884]),
        ("sand", .light, "platter.control", [0.4916739, 0.46305227, 0.37718713, 1.0]),
        ("sand", .light, "platter.dimControl", [0.64634, 0.6096205, 0.49946237, 0.8192941]),
        ("sand", .light, "platter.wash", [0.9, 0.85, 0.7, 0.32]),
        ("sand", .light, "platter.scrubber", [0.4916739, 0.46305227, 0.37718713, 1.0]),
        ("sand", .light, "page.primary", [0.24879342, 0.23288807, 0.18517175, 1.0]),
        ("sand", .light, "page.secondary", [0.18767375, 0.17496845, 0.13685203, 0.5984314]),
        ("sand", .light, "page.tertiary", [0.33784336, 0.3172757, 0.2555725, 0.40705884]),
        ("sand", .light, "page.control", [0.42837965, 0.4030718, 0.32714826, 1.0]),
        ("sand", .light, "page.dimControl", [0.33235455, 0.3120743, 0.25123316, 0.6586667]),
        ("sand", .light, "page.highlight", [0.9, 0.85, 0.7, 0.12]),
        ("sand", .light, "container.fill", [0.9, 0.85, 0.7, 1.0]),
        ("sand", .light, "container.wash", [0.9, 0.85, 0.7, 0.2]),
        ("sand", .light, "container.rim", [0.9, 0.85, 0.7, 0.24]),
        ("sand", .dark, "platter.wash", [0.9, 0.85, 0.7, 0.32]),
        ("sand", .dark, "page.highlight", [0.9, 0.85, 0.7, 0.16]),
    ]

    /// The palette at the shipped dials, whatever the tweak panel holds right now.
    static func palette(_ seed: Color?, _ scheme: ColorScheme, _ surface: CoverPalette.Surface) -> CoverPalette {
        CoverPalette(accent: seed, cast: seed, colorScheme: scheme, surface: surface, style: .standard, container: .standard, washOpacity: 0.32)
    }

    static func role(_ name: String) -> (CoverPalette.Surface, KeyPath<CoverPalette, Color?>) {
        let parts = name.split(separator: ".").map(String.init)
        let surface: CoverPalette.Surface = parts[0] == "page" ? .page : .platter
        let roles: [String: KeyPath<CoverPalette, Color?>] = [
            "primary": \.primary, "secondary": \.secondary, "tertiary": \.tertiary,
            "control": \.control, "dimControl": \.dimControl, "highlight": \.highlight,
            "wash": \.wash, "scrubber": \.control,
            "fill": \.accentContainer, "rim": \.containerRim,
        ]
        // The container's wash is its own role; the platter's wash is the accent pool.
        if name == "container.wash" { return (.page, \.containerWash) }
        return (surface, roles[parts[1]]!)
    }

    static func resolved(_ color: Color, _ scheme: ColorScheme) -> [Float] {
        var environment = EnvironmentValues()
        environment.colorScheme = scheme
        let c = color.resolve(in: environment)
        return [c.red, c.green, c.blue, c.opacity]
    }

    @Test func everyRoleResolvesAsItDidBeforeThePalette() throws {
        #expect(Self.before.count == Self.seeds.count * (16 + 2))
        for (seed, scheme, name, expected) in Self.before {
            let (surface, role) = Self.role(name)
            let color = try #require(Self.palette(Self.seeds[seed]!, scheme, surface)[keyPath: role], "\(seed) \(name) in \(scheme) is missing")
            #expect(Self.resolved(color, scheme) == expected, "\(seed) \(name) in \(scheme) changed")
        }
    }

    /// The simple roles are the very formulas they replaced, not just the same pixels.
    @Test func plainRolesAreTheFormulasTheyReplaced() {
        let style = CoverPaletteStyle.standard
        for accent in Self.seeds.values {
            for scheme in [ColorScheme.light, .dark] {
                let p = Self.palette(accent, scheme, .platter)
                // Light mode's content and controls are the mixes they replaced; dark mode's
                // are derived in OKLCH (`CoverPaletteDarkTests`).
                if scheme == .light {
                    #expect(p.primary == Color.black.mix(with: accent, by: 0.4))
                    #expect(p.secondary == Color.secondary.mix(with: accent, by: 0.4 * 0.5))
                    #expect(p.tertiary == Color(nsColor: .tertiaryLabelColor).mix(with: accent, by: 0.4 * 0.5))
                    #expect(p.control == Color.black.mix(with: accent, by: 0.64))
                    #expect(p.dimControl == Color.secondary.mix(with: accent, by: 0.64))
                }
                #expect(p.wash == accent.opacity(0.32))
                #expect(p.highlight == nil, "the platter has no playing row")
                #expect(p.onContainer == p.control)
                #expect(p.controlHover == p.control!.opacity(style.controlHoverOpacity))
                #expect(p.controlPressed == p.control!.opacity(style.controlPressedOpacity))
                #expect(p.hoverHighlightOpacity == 0.6)
                let page = Self.palette(accent, scheme, .page)
                #expect(page.highlight == accent.opacity(scheme == .dark ? 0.16 : 0.12))
            }
        }
    }

    /// The tuned shares, as the palette's defaults.
    @Test func defaultsAreTheTunedShares() {
        let style = CoverPaletteStyle.standard
        #expect(style.accentSaturation == 1.3)
        #expect(style.contentShare == 0.4 && style.dimContentRatio == 0.5 && style.controlShare == 0.64)
        #expect(style.highlightOpacity == 0.12 && style.darkHighlightOpacity == 0.16)
        #expect(style.hoverHighlightOpacity == 0.6 && style.contrastGuard)
    }

    /// No accent, no tinted roles: callers keep their plain label colours. The cast is its own
    /// seed, so a playlist's glass still catches its cover.
    @Test func aMissingSeedLeavesItsRolesPlain() {
        let cast = Color(red: 0.2, green: 0.5, blue: 0.9)
        for surface in [CoverPalette.Surface.platter, .page] {
            let p = CoverPalette(accent: nil, cast: cast, colorScheme: .dark, surface: surface, style: .standard, container: .standard, washOpacity: 0.32)
            #expect(p.primary == nil && p.secondary == nil && p.tertiary == nil)
            #expect(p.control == nil && p.dimControl == nil && p.onContainer == nil)
            #expect(p.highlight == nil && p.wash == nil)
            #expect(p.accentContainer != nil)
            #expect(p.controlHover == Color.white.opacity(0.05))
            let none = CoverPalette(accent: nil, cast: nil, colorScheme: .light, surface: surface, style: .standard, container: .standard, washOpacity: 0.32)
            #expect(none.accentContainer == nil && none.containerWash == nil && none.containerRim == nil)
        }
        #expect(EnvironmentValues().coverPalette == nil)
    }

    /// Only a page runs the guard; with it off, a page's shares are the platter's. (Yellow on a
    /// light page is where light mode's guard acts.)
    @Test func theGuardRunsOnPagesOnly() {
        let yellow = Self.seeds["yellow"]!
        let platter = Self.palette(yellow, .light, .platter)
        let page = Self.palette(yellow, .light, .page)
        #expect(platter.controlShare == 0.64)
        #expect(page.controlShare < 0.64)
        var unguarded = CoverPaletteStyle.standard
        unguarded.contrastGuard = false
        let raw = CoverPalette(accent: yellow, colorScheme: .light, surface: .page, style: unguarded, container: .standard, washOpacity: 0.32)
        #expect(raw.control == platter.control)
    }

    /// "Copy values" carries the palette's dials, and none of the per-surface tints it replaced.
    @Test func copyValuesCarriesThePalette() {
        let snippet = ArtworkStyle().swiftSnippet
        #expect(snippet.contains("palette = CoverPaletteStyle(accentSaturation: 1.30, contentShare: 0.40, dimContentRatio: 0.50, controlShare: 0.64, highlightOpacity: 0.12, darkHighlightOpacity: 0.16, hoverHighlightOpacity: 0.60, controlHoverOpacity: 0.050, controlPressedOpacity: 0.085, contrastGuard: true, darkPrimaryLightness: 0.87, darkControlLightness: 0.81, darkSecondaryLightness: 0.74, darkTertiaryLightness: 0.62, darkDimControlLightness: 0.58, darkChromaCap: 0.12)"))
        #expect(snippet.contains("darkLightness: 0.74, darkChromaCap: 0.18, darkRimOpacity: 0.40, darkWashScale: 1.20)"))
        #expect(!snippet.contains("pageTint") && !snippet.contains("textTint") && !snippet.contains("cornerAccentOpacity"))
    }
}
