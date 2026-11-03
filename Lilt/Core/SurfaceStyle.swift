import SwiftUI

/// The panel-surface values that can differ with what the panel is made of: the platter's glass
/// and tint, the lit rim every piece of glass wears, the blur and rim behind floating headers,
/// the cover's light at the top of a page, the header controls' rim and tint, and the ground the
/// cover's palette is lit for (`palette`). One of these
/// per window style and appearance (`SurfaceMatrix`), kept as data so a tuned set can be pasted
/// back as the shipped defaults (`SurfaceDefaults.json`).
///
/// How a surface works (which blur, which glass implementation, where a wash pools, whether the
/// platter always wears glass) stays in `ArtworkStyle`'s own styles; only strengths live here.
struct SurfaceStyle: Codable, Equatable {
    var platter: Platter
    var glassEdge: Edge
    var headerBlur: HeaderBlur
    var pageAmbient: PageAmbient
    var headerControls: HeaderControls
    var atRest: AtRest
    var palette: Palette

    /// The now-playing platter's finish (see `PlatterStyle` for the rest).
    struct Platter: Codable, Equatable {
        var shadowOpacity: Double
        /// Points.
        var shadowRadius: Double
        /// Points.
        var shadowOffsetY: Double
        /// The rim's strength, scaled up to the glass edge's (6× this, capped at full).
        var borderOpacity: Double
        /// The ambient fill: the artwork itself, blurred across the platter.
        var tintOpacity: Double
        var tintSaturation: Double
        /// Blur radius in points.
        var tintBlur: Double
        /// How much brighter the ambient fill gets while the pointer is over the platter.
        var hoverBrightness: Double
        /// The palette's wash of the accent (`CoverPalette.wash`).
        var washOpacity: Double
    }

    /// The lit rim of a piece of glass (`GlassEdge`): white catching light along the top, a
    /// fainter white through the middle, a dark line at the bottom.
    struct Edge: Codable, Equatable {
        var topOpacity: Double
        var middleOpacity: Double
        var bottomOpacity: Double
        /// Points, before any blur widens it.
        var lineWidth: Double
        /// Instead of the lit gradient, an even hairline of `hairlineWidth` points: white at
        /// `hairlineOpacity` added as light in dark mode (plus-lighter), black darkening in light
        /// (plus-darker). An experiment; off everywhere by default.
        var hairline: Bool
        var hairlineWidth: Double
        var hairlineOpacity: Double
    }

    /// The blur behind floating headers (see `HeaderBlurStyle` for which blur).
    struct HeaderBlur: Codable, Equatable {
        /// Blur radius in points at the top of the header.
        var radius: Double
        /// Saturation of what shows through (1 amplifies nothing).
        var saturation: Double
        /// Brightness shift of what shows through (-1...1).
        var brightness: Double
        /// How far below the header the blur reaches before fading to nothing, in points.
        var reach: Double
        /// The window rim redrawn over the blur; 1 is the full glass-edge highlight.
        var rimOpacity: Double
    }

    /// The cover's light spilling down from the top of a page (see `PageAmbientStyle`).
    struct PageAmbient: Codable, Equatable {
        var opacity: Double
        var saturation: Double
        /// Blur radius in points.
        var blur: Double
    }

    /// The header controls' surface (see `HeaderControlStyle` for which glass).
    struct HeaderControls: Codable, Equatable {
        /// Our lit hairline over the system's own edge treatment.
        var rim: Bool
        var rimOpacity: Double
        /// Tint of the glass with the cover's colour (0 = none).
        var tintOpacity: Double
    }
}

extension SurfaceStyle {
    /// The ground the cover's palette (`CoverPalette`) is lit for. Glass shows what's behind the
    /// window, so in dark mode its panel runs from near-black over a dark desktop to a mid grey
    /// (sRGB 0.45–0.5) over a light one, where the sidebar material of Normal and Solid stays
    /// near-black. A ladder tuned on near-black puts the dimmer lines at the mid grey's own
    /// lightness, so each surface carries its own ladder and the guard's stand-in for it.
    struct Palette: Codable, Equatable {
        /// The grey (sRGB, 0…1) the contrast guard measures a page's lines against, standing in
        /// for the panel as it usually renders.
        var guardBackdrop: Double
        /// Dark mode's OKLCH lightness per role. Light mode mixes shares of the accent into the
        /// label colours instead (`CoverPaletteStyle`) and has none.
        var darkLightness: DarkLightness?
    }

    /// Each dark-mode role's OKLCH lightness, title brightest; the role keeps the accent's hue,
    /// its chroma capped (`CoverPaletteStyle.darkChromaCap`) and lowered to what sRGB holds.
    struct DarkLightness: Codable, Equatable {
        var primary: Double
        var control: Double
        var secondary: Double
        var tertiary: Double
        var dimControl: Double

        /// The ladder for a near-black panel (Normal and Solid).
        static let darkPanel = DarkLightness(primary: 0.87, control: 0.81, secondary: 0.74, tertiary: 0.62, dimControl: 0.58)
    }
}

extension SurfaceStyle.Palette {
    /// The near-black dark panel and the light one: Normal's and Solid's, and the palette's
    /// own default where no window style is given.
    static func standard(_ scheme: ColorScheme) -> Self {
        scheme == .dark
            ? Self(guardBackdrop: 0.20, darkLightness: .darkPanel)
            : Self(guardBackdrop: 0.90, darkLightness: nil)
    }
}

extension SurfaceStyle {
    /// The panel at rest (Settings ▸ Appearance ▸ Fade when not in use, see `PanelRest`): how far
    /// the browse column recedes on this surface. On glass the desktop shows through what's
    /// left, on the solid style only the surface does, so each can take its own step.
    struct AtRest: Codable, Equatable {
        /// The browse column's opacity (its lists, header and search); the platter keeps 1.
        var contentOpacity: Double
    }
}

/// `SurfaceStyle` for every window style in each appearance: the shape of
/// `SurfaceDefaults.json`, `{ "glass": { "light": …, "dark": … }, "normal": …, "solid": … }`.
struct SurfaceMatrix: Codable, Equatable {
    var glass: Appearances
    var normal: Appearances
    var solid: Appearances

    struct Appearances: Codable, Equatable {
        var light: SurfaceStyle
        var dark: SurfaceStyle

        subscript(scheme: ColorScheme) -> SurfaceStyle {
            get { scheme == .dark ? dark : light }
            set { if scheme == .dark { dark = newValue } else { light = newValue } }
        }
    }

    subscript(style: WindowStyle) -> Appearances {
        get {
            switch style {
            case .glass: glass
            case .normal: normal
            case .solid: solid
            }
        }
        set {
            switch style {
            case .glass: glass = newValue
            case .normal: normal = newValue
            case .solid: solid = newValue
            }
        }
    }

    subscript(style: WindowStyle, scheme: ColorScheme) -> SurfaceStyle {
        get { self[style][scheme] }
        set { self[style][scheme] = newValue }
    }

    /// The bundled resource the shipped values come from.
    static let resource = "SurfaceDefaults"

    /// The shipped values, from the bundle. The file is part of the app, so failing to read it
    /// is a build mistake, not a state to recover from.
    static let defaults: SurfaceMatrix = {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "json") else {
            fatalError("\(resource).json is missing from the app bundle")
        }
        do {
            return try decode(Data(contentsOf: url))
        } catch {
            fatalError("\(resource).json doesn't decode: \(error)")
        }
    }()

    static func decode(_ data: Data) throws -> SurfaceMatrix {
        try JSONDecoder().decode(SurfaceMatrix.self, from: data)
    }

    /// The whole matrix as the resource file is written: pretty-printed with sorted keys, so a
    /// pasted export diffs cleanly against the shipped one.
    func json() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(self), as: UTF8.self) + "\n"
    }
}
