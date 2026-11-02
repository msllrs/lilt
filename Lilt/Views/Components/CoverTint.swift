import AppKit
import SwiftUI

/// A cover's colour as the platter's text and glyphs wear it: each label colour takes a share of
/// the accent, the title and controls from black or white, the dimmer lines from the secondary
/// and tertiary labels. One place for the mixing, so the platter, Up Next and an album page agree.
/// Nil wherever there's no accent (a cover with no colour to speak of): callers keep their plain
/// label colours.
struct CoverTint: Equatable {
    let accent: Color
    let colorScheme: ColorScheme
    /// How far each role moves from its label colour toward the accent (0 = plain label).
    var titleMix: Double
    var secondaryMix: Double
    var tertiaryMix: Double
    var controlMix: Double
    var dimControlMix: Double

    /// The title takes `textTint` of the accent and the dimmer lines half as much; the glyphs
    /// take `controlsTint`, bright or dim.
    init?(accent: Color?, colorScheme: ColorScheme, textTint: Double, controlsTint: Double) {
        guard let accent else { return nil }
        self.accent = accent
        self.colorScheme = colorScheme
        titleMix = textTint
        secondaryMix = textTint * 0.5
        tertiaryMix = textTint * 0.5
        controlMix = controlsTint
        dimControlMix = controlsTint
    }

    /// With the platter's own dials.
    init?(accent: Color?, colorScheme: ColorScheme, platter: PlatterStyle) {
        self.init(accent: accent, colorScheme: colorScheme, textTint: platter.textTint, controlsTint: platter.controlsTint)
    }

    /// White in dark mode, black in light: what the title and glyphs start from.
    var mono: Color { colorScheme == .dark ? .white : .black }

    var title: Color { mono.mix(with: accent, by: titleMix) }
    var secondary: Color { Color.secondary.mix(with: accent, by: secondaryMix) }
    var tertiary: Color { Color(nsColor: .tertiaryLabelColor).mix(with: accent, by: tertiaryMix) }
    var control: Color { mono.mix(with: accent, by: controlMix) }
    var dimControl: Color { Color.secondary.mix(with: accent, by: dimControlMix) }
}
