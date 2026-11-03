import SwiftUI

extension LeadingCastStyle {
    /// The cast colour as drawn: in dark mode the cover's hue at `darkLightness` in OKLCH, its
    /// chroma capped at `darkChromaCap`, so it adds clear coloured light to dark glass instead
    /// of a stain (too dim) or grey (lifted towards white); unchanged in light mode.
    func drawn(_ sampled: Color, dark: Bool) -> Color {
        guard dark else { return sampled }
        let seed = OKLCH(sampled, in: .dark)
        return OKLCH(l: darkLightness, c: min(seed.c, darkChromaCap), h: seed.h, opacity: seed.opacity).color
    }

    /// Wash and rim opacity for the scheme.
    func washOpacity(dark: Bool) -> Double { washOpacity * (dark ? darkWashScale : 1) }
    func rimOpacity(dark: Bool) -> Double { dark ? darkRimOpacity : rimOpacity }
    /// How far in from the outline the rim runs for the scheme (negative is outside).
    func rimInset(dark: Bool) -> Double { dark ? darkRimInset : rimInset }

    /// How the cast is composited: added as light on dark glass.
    func blend(dark: Bool) -> BlendMode { dark ? .plusLighter : .normal }
}
