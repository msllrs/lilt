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
    /// How much brighter the ambient fill gets while the pointer is over the platter (0 = none).
    var hoverBrightness: Double = 0.80
    /// A wash of the artwork's dominant colour in the top-leading corner, behind the cover.
    var cornerAccentOpacity: Double = 0.32
    /// Reach of that wash, as a fraction of the platter's size.
    var cornerAccentRadius: Double = 1.0
    /// Where the wash pools: the corner behind the cover, or the top edge's middle.
    var accentPlacement: AccentPlacement = .top
    /// How far the scrubber's elapsed line moves from the label colour toward the artwork's
    /// dominant colour (0 = plain black/white, 1 = fully coloured).
    var scrubberTint: Double = 1.0
    var scrubberSaturation: Double = 1.3
    /// Colour the scrubber like the glyphs instead (label colour with the controls' share of
    /// tint), ignoring `scrubberTint`.
    var scrubberLikeControls: Bool = true
    /// The same colour, more faintly, on the transport and mode glyphs (0 = label colour).
    var controlsTint: Double = 0.64
    /// And on the title and artist lines (the artist takes half of this).
    var textTint: Double = 0.4
    /// Give the platter's rim the play capsule's treatment: the cover's colour cast onto the lit
    /// top edge (using the capsule's rim mix, blur and blend)…
    var castEdge: Bool = true
    /// …and the capsule's soft wash of that colour inside, falling off from the top edge.
    var castGlow: Bool = false

    /// Tuned by Matt in the tweak panel on 2026-10-01; colour dials on 2026-10-02.
    static let standard = PlatterStyle()
}

/// How the hero artwork's colour is cast onto the Play capsule beneath it.
struct PlayCastStyle: Equatable {
    /// Saturation boost on the sampled artwork colour.
    var saturation: Double = 1.6
    /// Tint applied to the glass material itself.
    var tintOpacity: Double = 0.12
    /// How much of the colour goes into the lit top edge of the rim (0 = plain white).
    var rimMix: Double = 0.5
    /// A soft wash of the colour inside the capsule, falling off from the top edge.
    var glowOpacity: Double = 0.35
    /// Blur radius of that wash, in points.
    var glowBlur: Double = 10
    /// How far down the capsule the wash reaches, as a fraction of its height.
    var glowHeight: Double = 0.6
    /// Blur on the rim line itself; 0 is a crisp hairline, more turns it into a soft glow.
    var rimBlur: Double = 0
    var rimBlend: ArtworkBlend = .normal

    static let standard = PlayCastStyle()
}

/// Where the platter's dominant-colour wash sits.
enum AccentPlacement: String, CaseIterable, Identifiable {
    case corner, top
    var id: String { rawValue }
    var label: String { self == .corner ? "Corner" : "Top middle" }
    var unitPoint: UnitPoint { self == .corner ? .topLeading : .top }
}

/// The cover's light spilling down from the top of an album, artist or playlist page.
struct PageAmbientStyle: Equatable {
    /// Strength of the blurred cover wash at the very top.
    var opacity: Double = 0.28
    var saturation: Double = 3.0
    /// Blur radius in points.
    var blur: Double = 120
    /// How far down the page the wash reaches before fading out, in points.
    var reach: Double = 360

    static let standard = PageAmbientStyle()
}

/// The Dock tile while a track plays: the cover's colour on the plate and under the disc.
struct DockTileStyle: Equatable {
    /// Wash of the cover's colour over the plate, light at the top and strongest at the bottom
    /// (0 = plain plate).
    var plateTint: Double = 0.04
    var plateSaturation: Double = 1.2
    /// Coloured ambient shadow under the disc, as a fraction of the disc size.
    var shadowOpacity: Double = 0.40
    var shadowBlur: Double = 0.08
    var shadowOffsetY: Double = 0.04

    static let standard = DockTileStyle()
}

/// The header controls' surface (see `HeaderControlMode`), with AppKit's private glass dials.
struct HeaderControlStyle: Equatable {
    var mode: HeaderControlMode = .clear
    /// Also draw the search field in this mode (otherwise it keeps the flat fill).
    var appliesToSearch: Bool = true
    /// Our lit hairline over the system's own edge treatment.
    var rim: Bool = false
    var rimOpacity: Double = 0.5
    /// SwiftUI glass responds under the pointer.
    var interactive: Bool = true
    /// Tint the glass with the cover's colour (0 = none).
    var tintOpacity: Double = 0.6
    var tint: Color? = nil

    // NSGlassEffectView private knobs (AppKit mode only). Tuned by Matt in the tweak panel on
    // 2026-10-04 so flipping to AppKit lands on this look.
    /// `.clear` base style instead of `.regular`.
    var clearBase: Bool = true
    /// `_variant`: the glass recipe; 0 leaves whichever one the base style chose.
    var variant: Int = 3
    /// `_subvariant`: a named recipe (a string); empty leaves it unset.
    var subvariant: String = ""
    /// `_contentLensing`: refracts content behind the edge.
    var contentLensing: Bool = true
    /// `_scrimState`.
    var scrim: Int = 2
    /// `_subduedState`.
    var subdued: Int = 0
    /// `_interactionState`; only `interactionRange` is accepted.
    var interaction: Int = 0
    /// `_adaptiveAppearance` (2 is the default); only `adaptiveAppearanceRange` is accepted.
    var adaptiveAppearance: Int = 1
    /// `_useReducedShadowRadius`.
    var reducedShadow: Bool = false

    // Values AppKit's Swift enums behind these dials accept; anything else is a fatal error, so
    // the tweak panel offers these and `GlassSurface` clamps to them.
    static let variantRange = 0...20
    static let scrimRange = 0...3
    static let subduedRange = 0...3
    static let interactionRange = 0...2
    static let adaptiveAppearanceRange = 0...2

    static let standard = HeaderControlStyle()
}

/// The blur behind floating headers.
struct HeaderBlurStyle: Equatable {
    /// Use a Core Animation backdrop with a variable blur ramp (private API, guarded), rather
    /// than a system material faded out with a mask.
    var useBackdrop: Bool = true
    /// Blur radius in points at the top of the header.
    var radius: Double = 24
    /// Saturation of what shows through, like the system materials' boost.
    var saturation: Double = 1.4
    /// Brightness shift of what shows through (-1...1).
    var brightness: Double = 0.0
    /// How far below the header the blur reaches before fading to nothing.
    var reach: Double = 32
    /// Strength of the window rim redrawn over the blur (the backdrop blurs the glass's own
    /// hairline away); 1 is the full glass-edge highlight.
    var rimOpacity: Double = 0.45

    static let standard = HeaderBlurStyle()
}

/// How music notes are coloured.
enum NoteColorMode: String, CaseIterable, Identifiable {
    /// The label colour (black in light mode, white in dark).
    case label
    /// The current track's artwork colour.
    case artwork
    /// A slow walk around the hue wheel.
    case hueDrift

    var id: String { rawValue }

    var title: String {
        switch self {
        case .label: "Label"
        case .artwork: "Artwork"
        case .hueDrift: "Hue drift"
        }
    }
}

/// The music notes drifting out of the playing track's disc. Mirrors `CAEmitterCell`'s knobs;
/// fractions of a second, points per second, radians.
struct NotesStyle: Equatable {
    var colorMode: NoteColorMode = .artwork
    /// Seconds for one trip around the hue wheel in `hueDrift` mode.
    var huePeriod: Double = 8
    /// The emission angle swings this far either side of straight up, in radians (0 = off).
    var sway: Double = 0.5
    /// Seconds for one full left-right-left swing.
    var swayPeriod: Double = 3
    // Tuned by Matt in the tweak panel on 2026-10-02.
    /// Notes per second while playing.
    var birthRate: Double = 0.95
    var lifetime: Double = 2.42
    var lifetimeRange: Double = 0.4
    var velocity: Double = 16
    var velocityRange: Double = 18.86
    /// Spread either side of straight up, in radians.
    var spread: Double = 0.63
    /// Upward acceleration (positive rises faster).
    var gravity: Double = 6
    /// Sideways acceleration, for a lean.
    var drift: Double = 0
    /// Random variation in drift, either side of `drift`.
    var driftRange: Double = 0
    /// Glyph point size before scale.
    var glyphSize: Double = 18.06
    var scale: Double = 0.55
    var scaleRange: Double = 0.15
    /// Negative shrinks over life.
    var scaleSpeed: Double = -0.08
    /// Negative fades over life.
    var alphaSpeed: Double = -0.27
    var opacity: Double = 0.55
    var spin: Double = 0
    var spinRange: Double = 1.24
    /// Emission point relative to the disc centre, in points (y up).
    var sourceX: Double = 0
    var sourceY: Double = 12.92

    static let standard = NotesStyle()
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

    // Dark mode: a dark keyline vanishes against the dark container, so the edge goes light and
    // the separator works harder to lift artwork off the background.
    var darkKeylineOpacity: Double = 0.32
    var darkSeparatorOpacity: Double = 0.0

    var rowShadow: ShadowStyle = .row
    var playerShadow: ShadowStyle = .ambient
    var heroShadow: ShadowStyle = .ambient
    /// The small artwork in a page's collapsed header.
    var headerShadow: ShadowStyle = .header

    var platter: PlatterStyle = .standard
    var notes: NotesStyle = .standard
    var playCast: PlayCastStyle = .standard
    var headerBlur: HeaderBlurStyle = .standard
    var pageAmbient: PageAmbientStyle = .standard
    var dockTile: DockTileStyle = .standard
    var headerControls: HeaderControlStyle = .standard

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
        darkKeylineOpacity = 0.32
        darkSeparatorOpacity = 0.0
        rowShadow = .row
        playerShadow = .ambient
        heroShadow = .ambient
        headerShadow = .header
        platter = .standard
        notes = .standard
        playCast = .standard
        headerBlur = .standard
        pageAmbient = .standard
        dockTile = .standard
        headerControls = .standard
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
        darkKeylineOpacity = \(f(darkKeylineOpacity))
        darkSeparatorOpacity = \(f(darkSeparatorOpacity))
        rowShadow = \(snippet(rowShadow))
        playerShadow = \(snippet(playerShadow))
        heroShadow = \(snippet(heroShadow))
        headerShadow = \(snippet(headerShadow))
        platter = PlatterStyle(shadowOpacity: \(f(platter.shadowOpacity)), shadowRadius: \(f(platter.shadowRadius)), shadowOffsetY: \(f(platter.shadowOffsetY)), borderOpacity: \(f(platter.borderOpacity)), tintOpacity: \(f(platter.tintOpacity)), tintSaturation: \(f(platter.tintSaturation)), tintBlur: \(f(platter.tintBlur)), hoverBrightness: \(f(platter.hoverBrightness)), cornerAccentOpacity: \(f(platter.cornerAccentOpacity)), cornerAccentRadius: \(f(platter.cornerAccentRadius)), accentPlacement: .\(platter.accentPlacement.rawValue), scrubberTint: \(f(platter.scrubberTint)), scrubberSaturation: \(f(platter.scrubberSaturation)), scrubberLikeControls: \(platter.scrubberLikeControls), controlsTint: \(f(platter.controlsTint)), textTint: \(f(platter.textTint)), castEdge: \(platter.castEdge), castGlow: \(platter.castGlow))
        notes = NotesStyle(colorMode: .\(notes.colorMode.rawValue), huePeriod: \(f(notes.huePeriod)), sway: \(f(notes.sway)), swayPeriod: \(f(notes.swayPeriod)), birthRate: \(f(notes.birthRate)), lifetime: \(f(notes.lifetime)), lifetimeRange: \(f(notes.lifetimeRange)), velocity: \(f(notes.velocity)), velocityRange: \(f(notes.velocityRange)), spread: \(f(notes.spread)), gravity: \(f(notes.gravity)), drift: \(f(notes.drift)), driftRange: \(f(notes.driftRange)), glyphSize: \(f(notes.glyphSize)), scale: \(f(notes.scale)), scaleRange: \(f(notes.scaleRange)), scaleSpeed: \(f(notes.scaleSpeed)), alphaSpeed: \(f(notes.alphaSpeed)), opacity: \(f(notes.opacity)), spin: \(f(notes.spin)), spinRange: \(f(notes.spinRange)), sourceX: \(f(notes.sourceX)), sourceY: \(f(notes.sourceY)))
        playCast = PlayCastStyle(saturation: \(f(playCast.saturation)), tintOpacity: \(f(playCast.tintOpacity)), rimMix: \(f(playCast.rimMix)), glowOpacity: \(f(playCast.glowOpacity)), glowBlur: \(f(playCast.glowBlur)), glowHeight: \(f(playCast.glowHeight)), rimBlur: \(f(playCast.rimBlur)), rimBlend: .\(playCast.rimBlend.rawValue))
        headerBlur = HeaderBlurStyle(useBackdrop: \(headerBlur.useBackdrop), radius: \(f(headerBlur.radius)), saturation: \(f(headerBlur.saturation)), brightness: \(f(headerBlur.brightness)), reach: \(f(headerBlur.reach)), rimOpacity: \(f(headerBlur.rimOpacity)))
        pageAmbient = PageAmbientStyle(opacity: \(f(pageAmbient.opacity)), saturation: \(f(pageAmbient.saturation)), blur: \(f(pageAmbient.blur)), reach: \(f(pageAmbient.reach)))
        dockTile = DockTileStyle(plateTint: \(f(dockTile.plateTint)), plateSaturation: \(f(dockTile.plateSaturation)), shadowOpacity: \(f(dockTile.shadowOpacity)), shadowBlur: \(f(dockTile.shadowBlur)), shadowOffsetY: \(f(dockTile.shadowOffsetY)))
        headerControls = HeaderControlStyle(mode: .\(headerControls.mode.rawValue), appliesToSearch: \(headerControls.appliesToSearch), rim: \(headerControls.rim), rimOpacity: \(f(headerControls.rimOpacity)), interactive: \(headerControls.interactive), tintOpacity: \(f(headerControls.tintOpacity)), clearBase: \(headerControls.clearBase), variant: \(headerControls.variant), subvariant: "\(headerControls.subvariant)", contentLensing: \(headerControls.contentLensing), scrim: \(headerControls.scrim), subdued: \(headerControls.subdued), interaction: \(headerControls.interaction), adaptiveAppearance: \(headerControls.adaptiveAppearance), reducedShadow: \(headerControls.reducedShadow))
        """
    }

    private func snippet(_ s: ShadowStyle) -> String {
        "ShadowStyle(opacity: \(f(s.opacity)), blur: \(f(s.blur)), offsetY: \(f(s.offsetY)), spread: \(f(s.spread)), saturation: \(f(s.saturation)), lightCompensation: \(f(s.lightCompensation)), baseOpacity: \(f(s.baseOpacity)))"
    }

    private func f(_ value: Double) -> String { String(format: "%.2f", value) }
}
