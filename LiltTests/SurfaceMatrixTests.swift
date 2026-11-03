import SwiftUI
import Testing
@testable import Lilt

/// The panel-surface values per window style and appearance ship as `SurfaceDefaults.json`.
/// These pin the shipped file to the values the code held before it became data, written out
/// again here, so moving them into the file changed nothing on screen.
@MainActor
struct SurfaceMatrixTests {
    /// Today's values, as they were in `PlatterStyle`, `GlassEdge`, `HeaderBlurStyle`,
    /// `PageAmbientStyle` and `HeaderControlStyle`, and the palette's ground as it was in
    /// `CoverPalette.panelBackground` and `CoverPaletteStyle` (`glassDarkPalette` is Glass's own,
    /// see `CoverPaletteGlassDarkTests`).
    static func today(_ scheme: ColorScheme, palette: SurfaceStyle.Palette? = nil) -> SurfaceStyle {
        let dark = scheme == .dark
        return SurfaceStyle(
            platter: .init(shadowOpacity: 0.18, shadowRadius: 16, shadowOffsetY: 8, borderOpacity: 0.40, tintOpacity: 0.20, tintSaturation: 4.0, tintBlur: 160, hoverBrightness: 0.80, washOpacity: 0.32),
            glassEdge: .init(topOpacity: dark ? 0.45 : 0.9, middleOpacity: dark ? 0.12 : 0.35, bottomOpacity: dark ? 0.35 : 0.10, lineWidth: 1, hairline: false, hairlineWidth: 0.75, hairlineOpacity: 0.07),
            headerBlur: .init(radius: 24, saturation: 1.0, brightness: 0.0, reach: 32, rimOpacity: 0.45),
            pageAmbient: .init(opacity: 0.28, saturation: 3.0, blur: 120),
            headerControls: .init(rim: false, rimOpacity: 0.5, tintOpacity: 0.6),
            atRest: .init(contentOpacity: 0.6),
            palette: palette ?? (dark
                ? .init(guardBackdrop: 0.20, darkLightness: .init(primary: 0.87, control: 0.81, secondary: 0.74, tertiary: 0.62, dimControl: 0.58))
                : .init(guardBackdrop: 0.90, darkLightness: nil))
        )
    }

    /// Glass in dark mode: its panel can be a mid grey over a light desktop, so its ladder sits
    /// higher and its guard measures against a lighter stand-in.
    static let glassDarkPalette = SurfaceStyle.Palette(
        guardBackdrop: 0.40,
        darkLightness: .init(primary: 0.95, control: 0.93, secondary: 0.92, tertiary: 0.84, dimControl: 0.85)
    )

    static func shipped(_ style: Lilt.WindowStyle, _ scheme: ColorScheme) -> SurfaceStyle {
        today(scheme, palette: style == .glass && scheme == .dark ? glassDarkPalette : nil)
    }

    @Test func everyStyleStartsFromTodaysValues() {
        for style in WindowStyle.allCases {
            for scheme in [ColorScheme.light, .dark] {
                #expect(SurfaceMatrix.defaults[style, scheme] == Self.shipped(style, scheme), "\(style) in \(scheme) isn't today's look")
            }
        }
    }

    @Test func theMatrixRoundTripsThroughJSON() throws {
        var matrix = SurfaceMatrix.defaults
        matrix[.solid, .dark].platter.shadowOpacity = 0.31
        matrix[.normal, .light].headerControls.rim = true
        matrix[.glass, .light].glassEdge.topOpacity = 0.123456789
        let json = try matrix.json()
        #expect(try SurfaceMatrix.decode(Data(json.utf8)) == matrix)
        // Only the cells that were edited moved.
        #expect(matrix[.solid, .light] == SurfaceMatrix.defaults[.solid, .light])
        #expect(matrix[.glass, .dark] == SurfaceMatrix.defaults[.glass, .dark])
    }

    /// The export is the whole matrix, keyed style then appearance.
    @Test func theExportIsKeyedByStyleThenAppearance() throws {
        let json = try SurfaceMatrix.defaults.json()
        let object = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: [String: [String: Any]]])
        #expect(Set(object.keys) == ["glass", "normal", "solid"])
        for appearances in object.values {
            #expect(Set(appearances.keys) == ["light", "dark"])
            for surfaces in appearances.values {
                #expect(Set(surfaces.keys) == ["platter", "glassEdge", "headerBlur", "pageAmbient", "headerControls", "atRest", "palette"])
            }
        }
    }

    /// The shipped file is byte for byte what Export JSON writes, so a pasted export diffs only
    /// where values moved.
    @Test func theShippedFileIsWhatExportWrites() throws {
        let url = try #require(Bundle.main.url(forResource: SurfaceMatrix.resource, withExtension: "json"))
        #expect(try String(contentsOf: url, encoding: .utf8) == SurfaceMatrix.defaults.json())
    }

    @Test func aMissingValueDoesNotDecode() throws {
        let json = try SurfaceMatrix.defaults.json().replacingOccurrences(of: "\"washOpacity\"", with: "\"wash\"")
        #expect(throws: DecodingError.self) { try SurfaceMatrix.decode(Data(json.utf8)) }
    }

    /// The panel at rest reads its step from the surface file, per style and appearance.
    @Test func theRestingStepDecodesFromTheSurfaceFile() throws {
        for style in WindowStyle.allCases {
            for scheme in [ColorScheme.light, .dark] {
                #expect(SurfaceMatrix.defaults[style, scheme].atRest.contentOpacity == 0.6)
            }
        }
        let json = try SurfaceMatrix.defaults.json()
        let edited = json.replacingOccurrences(of: "\"contentOpacity\" : 0.6", with: "\"contentOpacity\" : 0.45")
        let matrix = try SurfaceMatrix.decode(Data(edited.utf8))
        #expect(matrix[.solid, .dark].atRest.contentOpacity == 0.45)
        let missing = json.replacingOccurrences(of: "\"contentOpacity\"", with: "\"opacity\"")
        #expect(throws: DecodingError.self) { try SurfaceMatrix.decode(Data(missing.utf8)) }
    }

    /// The hairline experiment adds light on dark glass and takes it away on light.
    @Test func theHairlineLightensDarkAndDarkensLight() {
        var edge = Self.today(.dark).glassEdge
        #expect(!edge.hairline, "the hairline is an experiment, off by default")
        edge.hairlineOpacity = 0.07
        let dark = GlassEdge<Circle>.hairline(edge, dark: true)
        let light = GlassEdge<Circle>.hairline(edge, dark: false)
        #expect(dark.color == Color.white.opacity(0.07) && dark.blend == .plusLighter)
        #expect(light.color == Color.black.opacity(0.07) && light.blend == .plusDarker)
    }

    /// Views read the cell for the style on screen: with Reduce Transparency on, glass is solid.
    @Test func viewsReadTheStyleOnScreen() {
        let saved = UserDefaults.standard.object(forKey: WindowStyle.key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: WindowStyle.key) } else { UserDefaults.standard.removeObject(forKey: WindowStyle.key) }
        }
        let style = ArtworkStyle()
        style.windowStyle = .glass
        style.surfaces[.glass, .dark].headerBlur.radius = 11
        style.surfaces[.solid, .dark].headerBlur.radius = 22
        #expect(style.surface(.dark, reduceTransparency: false).headerBlur.radius == 11)
        #expect(style.surface(.dark, reduceTransparency: true).headerBlur.radius == 22)
        #expect(style.surface(.light, reduceTransparency: false) == Self.today(.light))
        style.reset()
        #expect(style.surfaces == .defaults)
    }

    /// The platter's wash is the palette's, at the window style's strength.
    @Test func thePalettesWashFollowsTheWindowStyle() {
        let accent = Color(red: 0.85, green: 0.1, blue: 0.1)
        let shared = ArtworkStyle.shared
        let saved = shared.surfaces
        defer { shared.surfaces = saved }
        shared.surfaces = .defaults
        shared.surfaces[.solid, .light].platter.washOpacity = 0.5
        #expect(CoverPalette(accent: accent, colorScheme: .light, surface: .platter, windowStyle: .solid).wash == accent.opacity(0.5))
        #expect(CoverPalette(accent: accent, colorScheme: .light, surface: .platter, windowStyle: .normal).wash == accent.opacity(0.32))
    }
}
