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

    /// How strongly the playing row's pill takes the accent, over its plain fill (0 = plain).
    /// The platter has no such row; a page sets it.
    var highlightOpacity: Double = 0
    var highlight: Color { accent.opacity(highlightOpacity) }
}

// MARK: Contrast

extension CoverTint {
    /// The plain panel a page sits on, roughly, as a grey per scheme: a shade darker (light) or
    /// lighter (dark) than the sidebar material usually renders, so a colour that passes here
    /// passes on the real surface too. The platter sits on its own tinted glass and doesn't use
    /// this.
    static func panelBackground(_ scheme: ColorScheme) -> Double { scheme == .dark ? 0.20 : 0.90 }

    /// The least contrast each kind of line keeps on a page: body text's 4.5:1 for the title and
    /// the controls' labels, large text's 3:1 for the secondary lines, and about the system's own
    /// tertiary label in light mode for the faintest. A plain label already below its floor is
    /// held to where it was instead.
    static let titleFloor = 4.5
    static let secondaryFloor = 3.0
    static let tertiaryFloor = 1.8

    /// Each role's share of the accent, lowered where needed so the tinted colour keeps its
    /// floor against the panel. Without it, a saturated mid-tone pulled the controls' larger
    /// share toward the background (deep blue on dark, yellow on light) and the dimmer lines
    /// below what the plain labels manage.
    func guarded() -> CoverTint {
        var copy = self
        let tertiary = Color(nsColor: .tertiaryLabelColor)
        copy.titleMix = guardedMix(base: mono, mix: titleMix, minimum: Self.titleFloor)
        copy.secondaryMix = guardedMix(base: .secondary, mix: secondaryMix, minimum: Self.secondaryFloor)
        copy.tertiaryMix = guardedMix(base: tertiary, mix: tertiaryMix, minimum: Self.tertiaryFloor)
        copy.controlMix = guardedMix(base: mono, mix: controlMix, minimum: Self.titleFloor)
        copy.dimControlMix = guardedMix(base: .secondary, mix: dimControlMix, minimum: Self.secondaryFloor)
        return copy
    }

    /// The largest share up to `mix`, in small steps, that keeps the floor.
    private func guardedMix(base: Color, mix: Double, minimum: Double) -> Double {
        let floor = min(contrast(base), minimum)
        var share = mix
        while share > 0, contrast(base.mix(with: accent, by: share)) < floor {
            share = max(0, share - 0.02)
        }
        return share
    }

    /// WCAG contrast ratio of `color`, composited over the panel, against the panel.
    func contrast(_ color: Color) -> Double {
        var environment = EnvironmentValues()
        environment.colorScheme = colorScheme
        let c = color.resolve(in: environment)
        let ground = Self.panelBackground(colorScheme)
        let alpha = Double(c.opacity)
        func over(_ channel: Float) -> Double { Double(channel) * alpha + ground * (1 - alpha) }
        let fore = Self.luminance(over(c.red), over(c.green), over(c.blue))
        let back = Self.luminance(ground, ground, ground)
        return (max(fore, back) + 0.05) / (min(fore, back) + 0.05)
    }

    /// Relative luminance of a gamma-encoded sRGB colour.
    static func luminance(_ r: Double, _ g: Double, _ b: Double) -> Double {
        func linear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }
}

// MARK: Environment

extension EnvironmentValues {
    /// The page's cover colour for the text and glyphs that wear it (album pages only); nil
    /// keeps the plain label colours, as everywhere else.
    @Entry var coverTint: CoverTint? = nil
}

extension Optional where Wrapped == CoverTint {
    /// A role's colour when there's a tint, else the plain style it replaces.
    func style(_ role: KeyPath<CoverTint, Color>, or plain: some ShapeStyle) -> AnyShapeStyle {
        map { AnyShapeStyle($0[keyPath: role]) } ?? AnyShapeStyle(plain)
    }
}
