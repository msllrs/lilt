import SwiftUI

/// Blend modes the artwork finish can use, named so they can be shown in the tweak panel.
enum ArtworkBlend: String, CaseIterable, Identifiable {
    case plusLighter, softLight, screen, overlay, normal

    var id: String { rawValue }

    var blendMode: BlendMode {
        switch self {
        case .plusLighter: .plusLighter
        case .softLight: .softLight
        case .screen: .screen
        case .overlay: .overlay
        case .normal: .normal
        }
    }
}

/// How the artwork keyline picks its colour.
enum KeylineMode: String, CaseIterable, Identifiable {
    /// Dark on light-edged covers, light on dark-edged ones (sampled from the perimeter).
    case adaptive
    case dark
    case light
    case off

    var id: String { rawValue }
}

/// Where a piece of artwork is shown; each context gets its own shadow preset.
enum ArtworkContext: String, CaseIterable, Identifiable {
    case row, player, hero, header

    var id: String { rawValue }

    var label: String {
        switch self {
        case .row: "Rows"
        case .player: "Player"
        case .hero: "Pages"
        case .header: "Header"
        }
    }
}

/// Ambient shadow: a blurred, saturated copy of the artwork behind it, so the shadow carries the
/// cover's own colours. Fractions are relative to the artwork size.
struct ShadowStyle: Equatable {
    var opacity: Double
    var blur: Double
    var offsetY: Double
    var spread: Double
    var saturation: Double
    /// Darkens the ambient copy in proportion to how bright the artwork is, so near-white covers
    /// still cast something. 0 leaves light art shadowless; 1 pulls white down to mid-grey.
    var lightCompensation: Double = 0.4
    /// A plain dark shadow under the ambient one, grounding every cover regardless of colour.
    var baseOpacity: Double = 0.12

    // Tuned by Matt in the tweak panel on 2026-10-01.
    static let none = ShadowStyle(opacity: 0, blur: 0.16, offsetY: 0.08, spread: 0.92, saturation: 1, lightCompensation: 0.4, baseOpacity: 0)
    static let ambient = ShadowStyle(opacity: 0.88, blur: 0.16, offsetY: 0.08, spread: 0.92, saturation: 3.0, lightCompensation: 0.4, baseOpacity: 0.12)
    static let row = ShadowStyle(opacity: 0.40, blur: 0.16, offsetY: 0.08, spread: 0.92, saturation: 4.0, lightCompensation: 0.4, baseOpacity: 0.08)
    static let header = ShadowStyle(opacity: 0.64, blur: 0.16, offsetY: 0.08, spread: 0.92, saturation: 4.0, lightCompensation: 0.4, baseOpacity: 0.08)

    var isVisible: Bool { opacity > 0 || baseOpacity > 0 }
}

/// The now-playing platter's own finish. Shadow and border only appear while content scrolls
/// beneath it; the tint is a wash of the artwork's average colour.
struct PlatterStyle: Equatable {
    var shadowOpacity: Double = 0.18
    /// Points.
    var shadowRadius: Double = 16
    /// Points.
    var shadowOffsetY: Double = 8
    var borderOpacity: Double = 0.40
    /// The ambient fill: the artwork itself, blurred across the platter.
    var tintOpacity: Double = 0.20
    var tintSaturation: Double = 4.0
    /// Blur radius in points.
    var tintBlur: Double = 160

    /// Tuned by Matt in the tweak panel on 2026-10-01.
    static let standard = PlatterStyle()
}

/// The artwork finish: a spotlight falling from the top edge, a hairline inset border and a
/// per-context ambient shadow. Values are tunable live from the debug tweak panel; `reset()`
/// holds the shipped defaults.
@MainActor
@Observable
final class ArtworkStyle {
    static let shared = ArtworkStyle()

    // Spotlight: a radial light centred at (centerX, centerY) in unit coordinates, radius as a
    // multiple of the artwork size, fading from `peakOpacity` to clear.
    var spotlightCenterX: Double = 0.5
    var spotlightCenterY: Double = 0.0
    var spotlightRadius: Double = 1.0
    var spotlightOpacity: Double = 0.48
    var spotlightBlend: ArtworkBlend = .plusLighter

    // Edge: a crisp keyline one physical pixel wide, fully inset, in a neutral picked from the
    // artwork's own perimeter luminance (no blend modes: they shift colour unpredictably), plus
    // a very faint separator just outside against the surrounding surface.
    // Tuned by Matt on 2026-10-01: with the threshold at 0 the adaptive mode always picks the
    // dark keyline, so this is effectively black 20% inside plus a 20% separator outside.
    var keylineMode: KeylineMode = .adaptive
    /// Physical pixels.
    var keylineWidth: Double = 1
    var keylineDarkOpacity: Double = 0.20
    var keylineLightOpacity: Double = 0.40
    /// Perimeter luminance above which the keyline goes dark.
    var keylineThreshold: Double = 0.0
    var separatorOpacity: Double = 0.20

    var rowShadow: ShadowStyle = .row
    var playerShadow: ShadowStyle = .ambient
    var heroShadow: ShadowStyle = .ambient
    /// The small artwork in a page's collapsed header.
    var headerShadow: ShadowStyle = .header

    var platter: PlatterStyle = .standard

    func shadow(for context: ArtworkContext) -> ShadowStyle {
        switch context {
        case .row: rowShadow
        case .player: playerShadow
        case .hero: heroShadow
        case .header: headerShadow
        }
    }

    func setShadow(_ shadow: ShadowStyle, for context: ArtworkContext) {
        switch context {
        case .row: rowShadow = shadow
        case .player: playerShadow = shadow
        case .hero: heroShadow = shadow
        case .header: headerShadow = shadow
        }
    }

    /// Tuned by Matt in the tweak panel on 2026-10-01.
    func reset() {
        spotlightCenterX = 0.5
        spotlightCenterY = 0.0
        spotlightRadius = 1.0
        spotlightOpacity = 0.48
        spotlightBlend = .plusLighter
        keylineMode = .adaptive
        keylineWidth = 1
        keylineDarkOpacity = 0.20
        keylineLightOpacity = 0.40
        keylineThreshold = 0.0
        separatorOpacity = 0.20
        rowShadow = .row
        playerShadow = .ambient
        heroShadow = .ambient
        headerShadow = .header
        platter = .standard
    }

    /// The current values as Swift, ready to paste back into `reset()`.
    var swiftSnippet: String {
        """
        spotlightCenterX = \(f(spotlightCenterX))
        spotlightCenterY = \(f(spotlightCenterY))
        spotlightRadius = \(f(spotlightRadius))
        spotlightOpacity = \(f(spotlightOpacity))
        spotlightBlend = .\(spotlightBlend.rawValue)
        keylineMode = .\(keylineMode.rawValue)
        keylineWidth = \(f(keylineWidth))
        keylineDarkOpacity = \(f(keylineDarkOpacity))
        keylineLightOpacity = \(f(keylineLightOpacity))
        keylineThreshold = \(f(keylineThreshold))
        separatorOpacity = \(f(separatorOpacity))
        rowShadow = \(snippet(rowShadow))
        playerShadow = \(snippet(playerShadow))
        heroShadow = \(snippet(heroShadow))
        headerShadow = \(snippet(headerShadow))
        platter = PlatterStyle(shadowOpacity: \(f(platter.shadowOpacity)), shadowRadius: \(f(platter.shadowRadius)), shadowOffsetY: \(f(platter.shadowOffsetY)), borderOpacity: \(f(platter.borderOpacity)), tintOpacity: \(f(platter.tintOpacity)), tintSaturation: \(f(platter.tintSaturation)), tintBlur: \(f(platter.tintBlur)))
        """
    }

    private func snippet(_ s: ShadowStyle) -> String {
        "ShadowStyle(opacity: \(f(s.opacity)), blur: \(f(s.blur)), offsetY: \(f(s.offsetY)), spread: \(f(s.spread)), saturation: \(f(s.saturation)), lightCompensation: \(f(s.lightCompensation)), baseOpacity: \(f(s.baseOpacity)))"
    }

    private func f(_ value: Double) -> String { String(format: "%.2f", value) }
}
