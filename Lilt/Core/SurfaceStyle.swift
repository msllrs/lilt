import SwiftUI

/// The panel-surface values that can differ with what the panel is made of: the platter's glass
/// and tint, the lit rim every piece of glass wears, the blur and rim behind floating headers,
/// the cover's light at the top of a page, and the header controls' rim and tint. One of these
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
