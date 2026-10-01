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

/// The artwork finish: a spotlight falling from the top edge and a hairline inset border.
/// Values are tunable live from the debug tweak panel; `reset()` holds the shipped defaults.
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

    // Inset border: a uniform hairline on all edges, dark in light mode and light in dark mode.
    var borderWidth: Double = 1
    var borderOpacity: Double = 0.20
    var borderBlend: ArtworkBlend = .normal

    // Ambient shadow: a blurred, saturated copy of the artwork behind it, so the shadow carries
    // the cover's own colours. Fractions are relative to the artwork size.
    var shadowOpacity: Double = 0.45
    var shadowBlur: Double = 0.16
    var shadowOffsetY: Double = 0.08
    var shadowSpread: Double = 0.92
    var shadowSaturation: Double = 1.4
    /// Artwork smaller than this gets no shadow (row thumbnails stay crisp).
    var shadowMinSize: Double = 44

    /// Tuned by Matt in the tweak panel on 2026-10-01.
    func reset() {
        spotlightCenterX = 0.5
        spotlightCenterY = 0.0
        spotlightRadius = 1.0
        spotlightOpacity = 0.48
        spotlightBlend = .plusLighter
        borderWidth = 1
        borderOpacity = 0.20
        borderBlend = .normal
        shadowOpacity = 0.45
        shadowBlur = 0.16
        shadowOffsetY = 0.08
        shadowSpread = 0.92
        shadowSaturation = 1.4
        shadowMinSize = 44
    }

    /// The current values as Swift, ready to paste back into `reset()`.
    var swiftSnippet: String {
        """
        spotlightCenterX = \(f(spotlightCenterX))
        spotlightCenterY = \(f(spotlightCenterY))
        spotlightRadius = \(f(spotlightRadius))
        spotlightOpacity = \(f(spotlightOpacity))
        spotlightBlend = .\(spotlightBlend.rawValue)
        borderWidth = \(f(borderWidth))
        borderOpacity = \(f(borderOpacity))
        borderBlend = .\(borderBlend.rawValue)
        shadowOpacity = \(f(shadowOpacity))
        shadowBlur = \(f(shadowBlur))
        shadowOffsetY = \(f(shadowOffsetY))
        shadowSpread = \(f(shadowSpread))
        shadowSaturation = \(f(shadowSaturation))
        shadowMinSize = \(f(shadowMinSize))
        """
    }

    private func f(_ value: Double) -> String { String(format: "%.2f", value) }
}
