import AppKit
import SwiftUI

/// One set of named colours derived from a cover, the way a design system expands a seed colour
/// into roles: every surface that wears the cover reads its role here instead of mixing its own.
///
/// Two seeds come in, both already sampled from the cover (and interpolated between songs by
/// `InterpolatedColor`): the `accent`, the cover's dominant colour, and the `cast`, its average,
/// which lights the glass controls beneath it. Either can be nil (a cover with no colour to speak
/// of, or a page that doesn't wear its cover); the roles built from a missing seed are nil too,
/// and callers keep the plain style they had.
///
/// The roles:
/// - Content: `primary`, `secondary`, `tertiary`, a share of the accent mixed into the label
///   colours (the title and controls start from black or white, the dimmer lines from the
///   secondary and tertiary labels).
/// - Controls: `control` (glyphs, the scrubber), `dimControl` (a control that is off or can't be
///   used), and `controlHover` / `controlPressed` fills.
/// - Accent: `accent` itself, `accentContainer` (the cast as the glass controls wear it), with
///   its `containerWash` and `containerRim`, and `onContainer` for the glyph and label on it.
/// - Surfaces: `highlight` (the playing row's pill), `highlightFill` and `hoverHighlightOpacity`
///   (the plain pill beneath it and how much of it hover shows), and `wash` (the platter's pool
///   of the accent).
///
/// On a page the contrast guard runs once, here, as the palette is built (see `guarded`).
struct CoverPalette: Equatable {
    /// What the palette is laid over, which decides whether the contrast guard runs and whether
    /// there is a playing row to highlight.
    enum Surface: Equatable {
        /// The now-playing platter (and Up Next inside it, and Settings' miniature of it): its
        /// own tinted glass, which the guard's plain-panel ground doesn't describe.
        case platter
        /// A page on the plain panel (an album, and the back button beside it).
        case page
    }

    let accent: Color?
    private(set) var cast: Color?
    let colorScheme: ColorScheme
    let surface: Surface
    let style: CoverPaletteStyle
    /// The dials for the cast on glass controls (`LeadingCastStyle`).
    let container: LeadingCastStyle
    /// How strongly the platter's wash takes the accent, from the window style's surface values.
    let washOpacity: Double

    /// Each content and control role's share of the accent, after the guard.
    private(set) var primaryShare: Double
    private(set) var secondaryShare: Double
    private(set) var tertiaryShare: Double
    private(set) var controlShare: Double
    private(set) var dimControlShare: Double

    init(accent: Color?, cast: Color? = nil, colorScheme: ColorScheme, surface: Surface, style: CoverPaletteStyle, container: LeadingCastStyle, washOpacity: Double) {
        self.accent = accent
        self.cast = cast
        self.colorScheme = colorScheme
        self.surface = surface
        self.style = style
        self.container = container
        self.washOpacity = washOpacity
        primaryShare = style.contentShare
        secondaryShare = style.contentShare * style.dimContentRatio
        tertiaryShare = style.contentShare * style.dimContentRatio
        controlShare = style.controlShare
        dimControlShare = style.controlShare
        if surface == .page, style.contrastGuard { guardContrast() }
    }

    /// With the tweak panel's live dials, and the wash of `windowStyle` (the one chosen, unless
    /// a caller knows the one on screen) in `colorScheme`.
    @MainActor
    init(accent: Color?, cast: Color? = nil, colorScheme: ColorScheme, surface: Surface, windowStyle: WindowStyle? = nil) {
        let shared = ArtworkStyle.shared
        self.init(
            accent: accent, cast: cast, colorScheme: colorScheme, surface: surface,
            style: shared.palette, container: shared.leadingCast,
            washOpacity: shared.surfaces[windowStyle ?? shared.windowStyle, colorScheme].platter.washOpacity
        )
    }

    /// White in dark mode, black in light: what the title and glyphs start from.
    var mono: Color { colorScheme == .dark ? .white : .black }
    private var dark: Bool { colorScheme == .dark }
    private static var tertiaryLabel: Color { Color(nsColor: .tertiaryLabelColor) }

    // MARK: Content

    var primary: Color? { accent.map { mono.mix(with: $0, by: primaryShare) } }
    var secondary: Color? { accent.map { Color.secondary.mix(with: $0, by: secondaryShare) } }
    var tertiary: Color? { accent.map { Self.tertiaryLabel.mix(with: $0, by: tertiaryShare) } }

    // MARK: Controls

    var control: Color? { accent.map { mono.mix(with: $0, by: controlShare) } }
    var dimControl: Color? { accent.map { Color.secondary.mix(with: $0, by: dimControlShare) } }
    /// A control's fill under the pointer and while pressed: its glyph colour, faintly.
    var controlHover: Color { (control ?? mono).opacity(style.controlHoverOpacity) }
    var controlPressed: Color { (control ?? mono).opacity(style.controlPressedOpacity) }

    // MARK: Accent

    /// The cast as the glass controls wear it: in dark mode pushed in saturation and lifted
    /// towards white, so it adds light instead of staining (see `LeadingCastStyle.drawn`).
    var accentContainer: Color? { cast.map { container.drawn($0, dark: dark) } }
    /// The container's wash, falling off from its lit edge, and its lit rim.
    var containerWash: Color? { accentContainer?.opacity(container.washOpacity(dark: dark)) }
    var containerRim: Color? { accentContainer?.opacity(container.rimOpacity) }
    /// How the container's wash and rim are composited: added as light on dark glass.
    var containerBlend: BlendMode { container.blend(dark: dark) }
    /// The glyph and label on the container: the page's control colour.
    var onContainer: Color? { control }

    // MARK: Surfaces

    /// The playing row's pill over its plain fill. Only a page has a playing row.
    var highlight: Color? {
        guard surface == .page else { return nil }
        return accent?.opacity(dark ? style.darkHighlightOpacity : style.highlightOpacity)
    }
    /// The plain row pill the highlight sits on; a playing row shows it in full, hover shows
    /// `hoverHighlightOpacity` of it.
    var highlightFill: AnyShapeStyle { AnyShapeStyle(.fill.quaternary) }
    var hoverHighlightOpacity: Double { style.hoverHighlightOpacity }
    /// The platter's pool of the accent, behind the cover or along the top.
    var wash: Color? { accent?.opacity(washOpacity) }

    /// The same palette with another cast seed (the shares, and so the guard, are the accent's).
    func casting(_ cast: Color?) -> CoverPalette {
        var copy = self
        copy.cast = cast
        return copy
    }

    /// A role's colour when the palette has one, else the plain style it replaces.
    func style(_ role: KeyPath<CoverPalette, Color?>, or plain: some ShapeStyle) -> AnyShapeStyle {
        self[keyPath: role].map { AnyShapeStyle($0) } ?? AnyShapeStyle(plain)
    }
}

// MARK: Contrast

extension CoverPalette {
    /// The plain panel a page sits on, roughly, as a grey per scheme: a shade darker (light) or
    /// lighter (dark) than the sidebar material usually renders, so a colour that passes here
    /// passes on the real surface too.
    static func panelBackground(_ scheme: ColorScheme) -> Double { scheme == .dark ? 0.20 : 0.90 }

    /// The least contrast each kind of line keeps on a page: body text's 4.5:1 for the title and
    /// the controls' labels, large text's 3:1 for the secondary lines, and about the system's own
    /// tertiary label in light mode for the faintest. A plain label already below its floor is
    /// held to where it was instead.
    static let primaryFloor = 4.5
    static let secondaryFloor = 3.0
    static let tertiaryFloor = 1.8
    /// How finely a share is lowered while looking for one that keeps its floor.
    static let guardStep = 0.02

    /// Lowers each role's share of the accent where needed so the tinted colour keeps its floor
    /// against the panel. Without it, a saturated mid-tone pulled the controls' larger share
    /// toward the background (deep blue on dark, yellow on light) and the dimmer lines below what
    /// the plain labels manage.
    private mutating func guardContrast() {
        guard accent != nil else { return }
        primaryShare = guardedShare(base: mono, share: primaryShare, minimum: Self.primaryFloor)
        secondaryShare = guardedShare(base: .secondary, share: secondaryShare, minimum: Self.secondaryFloor)
        tertiaryShare = guardedShare(base: Self.tertiaryLabel, share: tertiaryShare, minimum: Self.tertiaryFloor)
        controlShare = guardedShare(base: mono, share: controlShare, minimum: Self.primaryFloor)
        dimControlShare = guardedShare(base: .secondary, share: dimControlShare, minimum: Self.secondaryFloor)
    }

    /// The largest share up to `share`, in small steps, that keeps the floor.
    private func guardedShare(base: Color, share: Double, minimum: Double) -> Double {
        guard let accent else { return share }
        let floor = min(contrast(base), minimum)
        var share = share
        while share > 0, contrast(base.mix(with: accent, by: share)) < floor {
            share = max(0, share - Self.guardStep)
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
    /// The page's palette for the text and glyphs that wear its cover (album pages only); nil
    /// keeps the plain label colours, as everywhere else.
    @Entry var coverPalette: CoverPalette? = nil
}

extension Optional where Wrapped == CoverPalette {
    /// A role's colour when there's a palette with that role, else the plain style it replaces.
    func style(_ role: KeyPath<CoverPalette, Color?>, or plain: some ShapeStyle) -> AnyShapeStyle {
        (self?[keyPath: role]).map { AnyShapeStyle($0) } ?? AnyShapeStyle(plain)
    }
}
