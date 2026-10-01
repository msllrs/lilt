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
    var spotlightRadius: Double = 0.85
    var spotlightOpacity: Double = 0.28
    var spotlightBlend: ArtworkBlend = .plusLighter

    // Inset border: brighter at the top where the light hits.
    var borderWidth: Double = 1
    var borderTopOpacity: Double = 0.45
    var borderBottomOpacity: Double = 0.06
    var borderBlend: ArtworkBlend = .overlay

    func reset() {
        spotlightCenterX = 0.5
        spotlightCenterY = 0.0
        spotlightRadius = 0.85
        spotlightOpacity = 0.28
        spotlightBlend = .plusLighter
        borderWidth = 1
        borderTopOpacity = 0.45
        borderBottomOpacity = 0.06
        borderBlend = .overlay
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
        borderTopOpacity = \(f(borderTopOpacity))
        borderBottomOpacity = \(f(borderBottomOpacity))
        borderBlend = .\(borderBlend.rawValue)
        """
    }

    private func f(_ value: Double) -> String { String(format: "%.2f", value) }
}
