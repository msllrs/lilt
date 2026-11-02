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
    case row, player, hero, header, avatar

    var id: String { rawValue }

    var label: String {
        switch self {
        case .row: "Rows"
        case .player: "Player"
        case .hero: "Pages"
        case .header: "Header"
        case .avatar: "Avatar"
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
    static let avatar = ShadowStyle(opacity: 0.64, blur: 0.16, offsetY: 0.08, spread: 0.64, saturation: 4.0, lightCompensation: 0.4, baseOpacity: 0.08)

    var isVisible: Bool { opacity > 0 || baseOpacity > 0 }
}

/// The now-playing platter's own finish. Its shadow, rim, ambient fill and wash strengths are
/// surface values, per window style and appearance (`SurfaceStyle.Platter`); these are the rest.
struct PlatterStyle: Equatable {
    /// Reach of the palette's wash (`CoverPalette.wash`), as a fraction of the platter's size.
    /// Its strength is the palette's.
    var cornerAccentRadius: Double = 1.0
    /// Where the wash pools: the corner behind the cover, or the top edge's middle.
    var accentPlacement: AccentPlacement = .top
    /// The platter's one override of its palette: the scrubber's elapsed line can take a share
    /// of the accent of its own (0 = plain black/white, 1 = fully coloured) instead of being
    /// coloured like the controls. Kept because the line is a thin mark that was tuned to read at
    /// the full accent. It ships unused: with `scrubberLikeControls` on, the line wears `control`.
    var scrubberTint: Double = 1.0
    var scrubberLikeControls: Bool = true
    /// Give the platter's rim the play capsule's treatment: the cover's colour cast onto the lit
    /// top edge (using the capsule's rim mix, blur and blend)…
    var castEdge: Bool = true
    /// …and the capsule's soft wash of that colour inside, falling off from the top edge.
    var castGlow: Bool = false
    /// The platter always wears its glass. Off restores the window-glass era rule, where it went
    /// bare whenever nothing scrolled beneath it.
    var alwaysGlass: Bool = true

    /// Tuned by Matt in the tweak panel on 2026-10-01; colour dials on 2026-10-02.
    static let standard = PlatterStyle()
}

/// The dials `CoverPalette` builds its roles from: each role's share of the cover's accent, and
/// the strengths of the rows that wear it (the platter's wash is a surface value, per window
/// style, in `SurfaceStyle.Platter`). One set for the platter, Up Next, album pages, the
/// back button and Settings' miniatures, so tuning one tunes them all.
struct CoverPaletteStyle: Equatable {
    /// Saturation boost on the cover's dominant colour as it is sampled for the accent.
    var accentSaturation: Double = 1.3
    /// How far the title moves from black or white toward the accent (0 = plain label)…
    var contentShare: Double = 0.4
    /// …and the fraction of that the secondary and tertiary lines take.
    var dimContentRatio: Double = 0.5
    /// The controls' share, bright (`control`) and dim (`dimControl`) alike.
    var controlShare: Double = 0.64
    /// The playing row's pill on a page: how much of the accent it takes, per scheme (0 = plain).
    var highlightOpacity: Double = 0.12
    var darkHighlightOpacity: Double = 0.16
    /// How much of the plain row pill hover shows (a playing row shows all of it).
    var hoverHighlightOpacity: Double = 0.6
    /// A control's fill under the pointer and while pressed, as a share of its glyph colour.
    /// Nothing draws these yet.
    var controlHoverOpacity: Double = 0.05
    var controlPressedOpacity: Double = 0.085
    /// On a page, lower a share where it would take a line below its contrast floor on the panel.
    var contrastGuard: Bool = true

    /// Tuned by Matt in the tweak panel on 2026-10-02 (as the platter's text and controls tint).
    static let standard = CoverPaletteStyle()
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

/// The cover's light spilling down from the top of an album, artist or playlist page. Its
/// strength, saturation and blur are surface values (`SurfaceStyle.PageAmbient`).
struct PageAmbientStyle: Equatable {
    /// The slice of the cover the wash is made from, as height over width: the platter's own
    /// wide shape is about 0.5, so the page's light comes from the same band of the cover and the
    /// two agree. 1 uses the whole cover.
    var band: Double = 0.5
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

/// The artwork colour the back button catches from the compact now-playing header beside it.
struct LeadingCastStyle: Equatable {
    /// The lit rim on the edge facing the artwork.
    // Tuned by Matt in the tweak panel on 2026-10-05.
    var rimOpacity: Double = 0.24
    var rimWidth: Double = 1.0
    /// Where across the button the rim starts to show (0 = leading edge, 1 = trailing edge).
    var rimStart: Double = 0.4
    /// The wash falling off from that edge across the button, and how far across it reaches
    /// (fraction of the button's width).
    var washOpacity: Double = 0.2
    var washReach: Double = 0.8
    /// Saturation boost on the sampled colour.
    var saturation: Double = 2.0
    /// Dark mode: how far the cast is lifted towards white before being added as light (a dim
    /// colour at low opacity over dark glass reads as a flat stain, not a lit edge), and how
    /// much of the light-mode wash opacity to use.
    var darkLighten: Double = 0.2
    var darkWashScale: Double = 0.8
    /// Dark mode: saturation multiplier applied before the lift, so the colour stays a colour
    /// rather than going pale as it brightens.
    var darkSaturation: Double = 1.5
    static let standard = LeadingCastStyle()
}

/// Settling the hero hand-off on a browse page: when a scroll ends part-way through the hero's
/// travel, the page glides to whichever end is nearer, so it never rests half-collapsed.
struct HeroSnapStyle: Equatable {
    var enabled: Bool = true
    /// Flicks slower than this (points per second) are not steered: scroll-wheel steps and slow
    /// releases rest where they are instead of being pulled back.
    var minFlick: Double = 40
    /// Travel within this much of either end is left alone (already effectively settled).
    var deadZone: Double = 0.04
    static let standard = HeroSnapStyle()
}

/// One soft band of light crossing a row once, leading edge to trailing, to confirm what its
/// menu just did (Copy Link, Play Next, Add to Queue). Clipped to the row's highlight shape.
/// Under Reduce Motion there's no sweep (see Theme.Motion.shine).
struct ShineStyle: Equatable, Sendable {
    /// Seconds for the band to cross the row.
    var duration: Double = 0.5
    /// The band's width as a share of the row's.
    var band: Double = 0.4
    /// Peak white at the band's centre: added light in dark mode, an overlay in light mode,
    /// which lifts what's beneath less than it would on dark, so it takes more.
    var darkOpacity: Double = 0.12
    var lightOpacity: Double = 0.45
    static let standard = ShineStyle()
}

/// What the panel itself is made of.
enum PanelSurface: String, CaseIterable, Identifiable {
    /// One sheet of Liquid Glass over the desktop; content and controls sit on the glass.
    case glass
    /// The sidebar material a Finder window uses: a content layer, so header controls can be the
    /// only glass and float over it, the way the system's own toolbars do.
    case sidebar
    var id: String { rawValue }
    var label: String {
        switch self {
        case .glass: "Window glass"
        case .sidebar: "Sidebar material"
        }
    }
}

struct PanelStyle: Equatable {
    var surface: PanelSurface = .glass
    /// Sidebar only: the desktop shows through, as it does behind a Finder sidebar. Off gives the
    /// flat look of an inactive window (the same choice Reduce Transparency makes).
    var translucent: Bool = true
    static let standard = PanelStyle()

    /// What goes on screen. With the system's Reduce Transparency on, glass gives way to the flat
    /// sidebar: content sits directly on the window glass, which would still let the desktop show
    /// through behind the rows, and the inactive material is the look the system asks for.
    func effective(reduceTransparency: Bool) -> PanelStyle {
        reduceTransparency && surface == .glass ? WindowStyle.solid.panelStyle : self
    }
}

/// Settings ▸ Appearance ▸ Window style: the three looks `PanelStyle` can actually produce
/// (glass ignores `translucent`, so it has no solid twin). Stored by name; the debug tweak panel
/// edits the same `ArtworkStyle.panel`, so the two stay in step.
enum WindowStyle: String, CaseIterable, Identifiable {
    /// Window-wide Liquid Glass.
    case glass
    /// The Finder sidebar material, with the desktop showing through.
    case normal
    /// The same material, flat and opaque.
    case solid

    static let key = "windowStyle"
    /// Liquid Glass until someone picks another look.
    static let standard = WindowStyle.glass

    var id: String { rawValue }

    var title: String {
        switch self {
        case .glass: "Glass"
        case .normal: "Normal"
        case .solid: "Solid"
        }
    }

    var panelStyle: PanelStyle {
        switch self {
        case .glass: PanelStyle(surface: .glass, translucent: true)
        case .normal: PanelStyle(surface: .sidebar, translucent: true)
        case .solid: PanelStyle(surface: .sidebar, translucent: false)
        }
    }

    init(_ panel: PanelStyle) {
        switch panel.surface {
        case .glass: self = .glass
        case .sidebar: self = panel.translucent ? .normal : .solid
        }
    }

    /// The stored choice; a missing or unknown name is today's look.
    static func stored(in defaults: UserDefaults = .standard) -> WindowStyle {
        defaults.string(forKey: key).flatMap(WindowStyle.init(rawValue:)) ?? standard
    }

    func store(in defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.key)
    }
}

/// The header controls' surface (see `HeaderControlMode`), with AppKit's private glass dials.
/// Their rim and cover tint strengths are surface values (`SurfaceStyle.HeaderControls`).
struct HeaderControlStyle: Equatable {
    var mode: HeaderControlMode = .clear
    /// Also draw the search field in this mode (otherwise it keeps the flat fill).
    var appliesToSearch: Bool = true
    /// SwiftUI glass responds under the pointer.
    var interactive: Bool = true
    /// The cover's colour handed to the glass, already at the surface's tint strength.
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

/// The blur behind floating headers. Its radius, saturation, brightness, reach and rim are
/// surface values (`SurfaceStyle.HeaderBlur`): a saturation of 1 blurs what is there and
/// amplifies nothing (a boost turned the cover's wash under the header into a strong cast of its
/// own), and the rim is the window's, redrawn over the blur that hides it.
struct HeaderBlurStyle: Equatable {
    /// Use a Core Animation backdrop with a variable blur ramp (private API, guarded), rather
    /// than a system material faded out with a mask.
    var useBackdrop: Bool = true
    /// Blur Lilt's own layers only, rendered in-process, instead of letting the window server
    /// composite the backdrop from everything beneath it. Off: in-process, the capture includes
    /// the sidebar material's tint layer, and painting the blurred result back over the same
    /// material applied the tint twice, a darker band over the rows with a visible edge.
    var ownContentOnly: Bool = false

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

    /// The panel's surface as Settings names it. Writing it sets `panel`, which saves the choice.
    var windowStyle: WindowStyle {
        get { WindowStyle(panel) }
        set { panel = newValue.panelStyle }
    }

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
    /// The account avatar in the library header: a round picture beside glass controls. Tuned by
    /// Matt in the tweak panel on 2026-10-05: tighter spread than the header artwork.
    var avatarShadow: ShadowStyle = .avatar

    var platter: PlatterStyle = .standard
    var palette: CoverPaletteStyle = .standard
    var notes: NotesStyle = .standard
    var playCast: PlayCastStyle = .standard
    var headerBlur: HeaderBlurStyle = .standard
    var pageAmbient: PageAmbientStyle = .standard
    var dockTile: DockTileStyle = .standard
    var headerControls: HeaderControlStyle = .standard
    /// Starts from Settings ▸ Appearance ▸ Window style and saves every change back there, so
    /// the tweak panel and Settings edit one value and the open panel restyles at once.
    var panel: PanelStyle = WindowStyle.stored().panelStyle {
        didSet { WindowStyle(panel).store() }
    }
    var leadingCast: LeadingCastStyle = .standard
    /// The panel-surface values for every window style and appearance, from
    /// `SurfaceDefaults.json`. The tweak panel edits the cell on screen.
    var surfaces: SurfaceMatrix = .defaults
    /// Library title centred between the back button and the avatar, rather than leading.
    var centredLibraryTitle: Bool = true
    var heroSnap: HeroSnapStyle = .standard
    var shine: ShineStyle = .standard

    /// The window style actually on screen: with Reduce Transparency on, glass shows as solid.
    func shownWindowStyle(reduceTransparency: Bool) -> WindowStyle {
        WindowStyle(panel.effective(reduceTransparency: reduceTransparency))
    }

    /// The surface values for the window style on screen, in `scheme`.
    func surface(_ scheme: ColorScheme, reduceTransparency: Bool) -> SurfaceStyle {
        surfaces[shownWindowStyle(reduceTransparency: reduceTransparency), scheme]
    }

    func shadow(for context: ArtworkContext) -> ShadowStyle {
        switch context {
        case .row: rowShadow
        case .player: playerShadow
        case .hero: heroShadow
        case .header: headerShadow
        case .avatar: avatarShadow
        }
    }

    func setShadow(_ shadow: ShadowStyle, for context: ArtworkContext) {
        switch context {
        case .row: rowShadow = shadow
        case .player: playerShadow = shadow
        case .hero: heroShadow = shadow
        case .header: headerShadow = shadow
        case .avatar: avatarShadow = shadow
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
        avatarShadow = .avatar
        platter = .standard
        palette = .standard
        notes = .standard
        playCast = .standard
        headerBlur = .standard
        pageAmbient = .standard
        dockTile = .standard
        headerControls = .standard
        panel = .standard
        leadingCast = .standard
        surfaces = .defaults
        centredLibraryTitle = true
        heroSnap = .standard
        shine = .standard
    }

    /// The current values as Swift, ready to paste back into `reset()`. The surface values are
    /// data, not Swift: the tweak panel's Export JSON copies those for `SurfaceDefaults.json`.
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
        avatarShadow = \(snippet(avatarShadow))
        platter = PlatterStyle(cornerAccentRadius: \(f(platter.cornerAccentRadius)), accentPlacement: .\(platter.accentPlacement.rawValue), scrubberTint: \(f(platter.scrubberTint)), scrubberLikeControls: \(platter.scrubberLikeControls), castEdge: \(platter.castEdge), castGlow: \(platter.castGlow), alwaysGlass: \(platter.alwaysGlass))
        palette = CoverPaletteStyle(accentSaturation: \(f(palette.accentSaturation)), contentShare: \(f(palette.contentShare)), dimContentRatio: \(f(palette.dimContentRatio)), controlShare: \(f(palette.controlShare)), highlightOpacity: \(f(palette.highlightOpacity)), darkHighlightOpacity: \(f(palette.darkHighlightOpacity)), hoverHighlightOpacity: \(f(palette.hoverHighlightOpacity)), controlHoverOpacity: \(f3(palette.controlHoverOpacity)), controlPressedOpacity: \(f3(palette.controlPressedOpacity)), contrastGuard: \(palette.contrastGuard))
        notes = NotesStyle(colorMode: .\(notes.colorMode.rawValue), huePeriod: \(f(notes.huePeriod)), sway: \(f(notes.sway)), swayPeriod: \(f(notes.swayPeriod)), birthRate: \(f(notes.birthRate)), lifetime: \(f(notes.lifetime)), lifetimeRange: \(f(notes.lifetimeRange)), velocity: \(f(notes.velocity)), velocityRange: \(f(notes.velocityRange)), spread: \(f(notes.spread)), gravity: \(f(notes.gravity)), drift: \(f(notes.drift)), driftRange: \(f(notes.driftRange)), glyphSize: \(f(notes.glyphSize)), scale: \(f(notes.scale)), scaleRange: \(f(notes.scaleRange)), scaleSpeed: \(f(notes.scaleSpeed)), alphaSpeed: \(f(notes.alphaSpeed)), opacity: \(f(notes.opacity)), spin: \(f(notes.spin)), spinRange: \(f(notes.spinRange)), sourceX: \(f(notes.sourceX)), sourceY: \(f(notes.sourceY)))
        playCast = PlayCastStyle(saturation: \(f(playCast.saturation)), tintOpacity: \(f(playCast.tintOpacity)), rimMix: \(f(playCast.rimMix)), glowOpacity: \(f(playCast.glowOpacity)), glowBlur: \(f(playCast.glowBlur)), glowHeight: \(f(playCast.glowHeight)), rimBlur: \(f(playCast.rimBlur)), rimBlend: .\(playCast.rimBlend.rawValue))
        headerBlur = HeaderBlurStyle(useBackdrop: \(headerBlur.useBackdrop), ownContentOnly: \(headerBlur.ownContentOnly))
        pageAmbient = PageAmbientStyle(band: \(f(pageAmbient.band)), reach: \(f(pageAmbient.reach)))
        dockTile = DockTileStyle(plateTint: \(f(dockTile.plateTint)), plateSaturation: \(f(dockTile.plateSaturation)), shadowOpacity: \(f(dockTile.shadowOpacity)), shadowBlur: \(f(dockTile.shadowBlur)), shadowOffsetY: \(f(dockTile.shadowOffsetY)))
        headerControls = HeaderControlStyle(mode: .\(headerControls.mode.rawValue), appliesToSearch: \(headerControls.appliesToSearch), interactive: \(headerControls.interactive), clearBase: \(headerControls.clearBase), variant: \(headerControls.variant), subvariant: "\(headerControls.subvariant)", contentLensing: \(headerControls.contentLensing), scrim: \(headerControls.scrim), subdued: \(headerControls.subdued), interaction: \(headerControls.interaction), adaptiveAppearance: \(headerControls.adaptiveAppearance), reducedShadow: \(headerControls.reducedShadow))
        panel = PanelStyle(surface: .\(panel.surface.rawValue), translucent: \(panel.translucent))
        centredLibraryTitle = \(centredLibraryTitle)
        heroSnap = HeroSnapStyle(enabled: \(heroSnap.enabled), minFlick: \(f(heroSnap.minFlick)), deadZone: \(f(heroSnap.deadZone)))
        shine = ShineStyle(duration: \(f(shine.duration)), band: \(f(shine.band)), darkOpacity: \(f(shine.darkOpacity)), lightOpacity: \(f(shine.lightOpacity)))
        leadingCast = LeadingCastStyle(rimOpacity: \(f(leadingCast.rimOpacity)), rimWidth: \(f(leadingCast.rimWidth)), rimStart: \(f(leadingCast.rimStart)), washOpacity: \(f(leadingCast.washOpacity)), washReach: \(f(leadingCast.washReach)), saturation: \(f(leadingCast.saturation)), darkLighten: \(f(leadingCast.darkLighten)), darkWashScale: \(f(leadingCast.darkWashScale)), darkSaturation: \(f(leadingCast.darkSaturation)))
        """
    }

    private func snippet(_ s: ShadowStyle) -> String {
        "ShadowStyle(opacity: \(f(s.opacity)), blur: \(f(s.blur)), offsetY: \(f(s.offsetY)), spread: \(f(s.spread)), saturation: \(f(s.saturation)), lightCompensation: \(f(s.lightCompensation)), baseOpacity: \(f(s.baseOpacity)))"
    }

    private func f(_ value: Double) -> String { String(format: "%.2f", value) }
    /// For the fine fills, which live below a hundredth's resolution.
    private func f3(_ value: Double) -> String { String(format: "%.3f", value) }
}
