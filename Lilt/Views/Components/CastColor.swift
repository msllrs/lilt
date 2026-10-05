import AppKit
import SwiftUI

extension LeadingCastStyle {
    /// The cast colour as drawn: in dark mode pushed in saturation and lifted towards white, so
    /// it adds light to dark glass instead of staining it; unchanged in light mode.
    func drawn(_ sampled: Color, dark: Bool) -> Color {
        guard dark else { return sampled }
        return Self.saturated(sampled, by: darkSaturation).mix(with: .white, by: darkLighten)
    }

    /// Wash opacity for the scheme.
    func washOpacity(dark: Bool) -> Double { washOpacity * (dark ? darkWashScale : 1) }

    /// How the cast is composited: added as light on dark glass.
    func blend(dark: Bool) -> BlendMode { dark ? .plusLighter : .normal }

    /// The colour with its saturation multiplied (clamped), brightness untouched.
    static func saturated(_ color: Color, by factor: Double) -> Color {
        guard let c = NSColor(color).usingColorSpace(.sRGB) else { return color }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(nsColor: NSColor(hue: h, saturation: min(1, s * factor), brightness: b, alpha: a))
    }
}
