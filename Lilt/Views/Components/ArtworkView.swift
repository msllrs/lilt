import SwiftUI

/// Album/artist artwork with a Sleeve-style finish: a spotlight from the top, a hairline inset
/// border and an ambient shadow in the artwork's own colours. Images come from `ImageCache`, so
/// revisiting a row never flashes a placeholder, and a smaller cached rendition stands in,
/// blurred, while a larger one loads.
/// How a picture turns inside its sleeve: an angle that is a function of time, which Core
/// Animation plays out (see `SpinningPicture`), so the clock never ticks through SwiftUI.
struct ArtworkSpin: Equatable {
    /// The angle when the clock last started, or where the picture rests.
    var baseAngle: Double
    /// When the clock started; nil holds `baseAngle`.
    var resumedAt: Date?
    var degreesPerSecond: Double
    /// Stops the clock without forgetting where it was (a parked screen).
    var paused: Bool

    func angle(at date: Date) -> Angle {
        guard let resumedAt else { return .degrees(baseAngle) }
        return .degrees(baseAngle + date.timeIntervalSince(resumedAt) * degreesPerSecond)
    }

    /// True while the picture should be moving.
    var isTurning: Bool { resumedAt != nil && !paused }
}

struct ArtworkView: View {
    let url: URL?
    let size: CGFloat
    let radius: CGFloat
    /// Picks the shadow preset (rows, player, pages).
    var context: ArtworkContext = .row
    /// Spins the picture inside the sleeve; the lighting, keyline and shadow stay put.
    var spin: ArtworkSpin? = nil

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @State private var image: NSImage?
    /// True while `image` is a stand-in rendition at another size.
    @State private var isStandIn = false

    init(url: URL?, size: CGFloat, radius: CGFloat, context: ArtworkContext = .row, spin: ArtworkSpin? = nil) {
        self.url = url
        self.size = size
        self.radius = radius
        self.context = context
        self.spin = spin
        // Seed synchronously so a cache hit renders on the first frame. The same cover decoded
        // smaller (a row's, under the hero) stands in like another size of it.
        let pixels = ImageCache.pixels(forPoints: size)
        let seed = MainActor.assumeIsolated { () -> (NSImage?, Bool) in
            guard let url else { return (nil, false) }
            if let hit = ImageCache.shared.cached(url, pixels: pixels) { return (hit, false) }
            if let variant = ImageCache.shared.cached(url) ?? ImageCache.shared.anyVariant(for: url) { return (variant, true) }
            return (nil, false)
        }
        _image = State(initialValue: seed.0)
        _isStandIn = State(initialValue: seed.1)
    }

    /// How much to blur a stand-in: nothing if it already has (nearly) enough pixels for this
    /// size, ramping up only when it's genuinely undersized. Keeps a 240px cover standing in for
    /// a 140pt hero from pulsing blur-then-sharp on every page open.
    private var standInBlur: CGFloat {
        guard isStandIn, let image else { return 0 }
        let pixels = CGFloat(image.representations.first?.pixelsWide ?? Int(image.size.width))
        let needed = size * (NSScreen.main?.backingScaleFactor ?? 2)
        let ratio = min(pixels / max(needed, 1), 1)
        return ratio >= 0.8 ? 0 : size * 0.12 * (1 - ratio)
    }

    private var style: ArtworkStyle { .shared }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: radius, style: .continuous) }

    /// One physical pixel (times the tweakable width), so the keyline stays crisp on Retina
    /// instead of becoming a two-pixel grey band.
    private var keylineWidth: CGFloat { CGFloat(style.keylineWidth) / max(displayScale, 1) }

    /// Neutral keyline picked from the artwork's perimeter: dark on pale edges, light on dark.
    /// In dark mode the edge is always light, since a dark line vanishes against the container.
    private var keyline: Color? {
        if style.keylineMode == .off { return nil }
        if colorScheme == .dark { return .white.opacity(style.darkKeylineOpacity) }
        switch style.keylineMode {
        case .off: return nil
        case .dark: return .black.opacity(style.keylineDarkOpacity)
        case .light: return .white.opacity(style.keylineLightOpacity)
        case .adaptive:
            return (url.map { ImageCache.shared.edgeLuminance(for: $0) } ?? 0.5) > style.keylineThreshold
                ? .black.opacity(style.keylineDarkOpacity)
                : .white.opacity(style.keylineLightOpacity)
        }
    }

    private var separatorOpacity: Double {
        colorScheme == .dark ? style.darkSeparatorOpacity : style.separatorOpacity
    }

    var body: some View {
        ZStack {
            if let image {
                sleeve(image)
                    .transition(.opacity)
            } else {
                placeholder
                    .transition(.opacity)
            }
        }
        .animation(Theme.Motion.quick, value: image == nil)
        .frame(width: size, height: size)
        .task(id: url) { await load() }
    }

    private func sleeve(_ image: NSImage) -> some View {
        let picture = Image(nsImage: image)
        return Group {
            if let spin {
                // Turned by Core Animation: once it is going, nothing here, in the sleeve or in
                // the row around it is re-evaluated until the spin changes.
                SpinningPicture(image: image, spin: spin, scale: displayScale)
                    .frame(width: size, height: size)
                    .blur(radius: standInBlur)
                    // Swapping in for the flat picture (both upright, the same pixels) must
                    // not cross-fade, or the cover dims for a moment as the disc starts.
                    .transition(.identity)
            } else {
                picture.resizable().aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    // A genuinely undersized stand-in is blurred to hide the resampling until
                    // the real one lands; a near-enough one is shown as is.
                    .blur(radius: standInBlur)
                    .transition(.identity)
            }
        }
            .overlay(spotlight)
            .clipShape(shape)
            .overlay(insetKeyline)
            .overlay(outerSeparator)
            .background { ambientShadow(picture) }
            .animation(Theme.Motion.quick, value: isStandIn)
    }

    /// What this drawing decodes its cover at.
    private var pixels: Int { ImageCache.pixels(forPoints: size) }

    private func load() async {
        guard let url else { image = nil; return }
        if let hit = ImageCache.shared.cached(url, pixels: pixels) {
            image = hit
            isStandIn = false
            return
        }
        if let variant = ImageCache.shared.cached(url) ?? ImageCache.shared.anyVariant(for: url) {
            image = variant
            isStandIn = true
        } else if image != nil {
            // Nothing cached for the new URL: keep the previous picture, blurred, rather than
            // dropping to the placeholder while the real one loads.
            isStandIn = true
        }
        guard let loaded = await ImageCache.shared.load(url, maxPixels: pixels), !Task.isCancelled else { return }
        withAnimation(Theme.Motion.quick) {
            image = loaded
            isStandIn = false
        }
    }

    /// A radial light from the top edge. `plusLighter` lifts the artwork's own hues instead of
    /// washing them out with white.
    private var spotlight: some View {
        RadialGradient(
            stops: [
                .init(color: .white.opacity(style.spotlightOpacity), location: 0),
                .init(color: .white.opacity(style.spotlightOpacity * 0.35), location: 0.45),
                .init(color: .clear, location: 1),
            ],
            center: UnitPoint(x: style.spotlightCenterX, y: style.spotlightCenterY),
            startRadius: 0,
            endRadius: size * style.spotlightRadius
        )
        .blendMode(style.spotlightBlend.blendMode)
    }

    /// Crisp inset keyline, one physical pixel, no blend mode.
    @ViewBuilder
    private var insetKeyline: some View {
        if let keyline {
            shape.strokeBorder(keyline, lineWidth: keylineWidth)
        }
    }

    /// A barely-there line just outside the artwork, separating it from whatever surface it
    /// sits on, in the surface's own foreground tone.
    @ViewBuilder
    private var outerSeparator: some View {
        if separatorOpacity > 0 {
            shape.inset(by: -keylineWidth / 2)
                .stroke(Color.primary.opacity(separatorOpacity), lineWidth: keylineWidth)
        }
    }

    /// The artwork's own colours, blurred and pushed down behind it. Spills past the frame on
    /// purpose; that's what a shadow does.
    @ViewBuilder
    private func ambientShadow(_ picture: Image) -> some View {
        let shadow = style.shadow(for: context)
        if shadow.isVisible {
            // Brighter covers get pulled darker so a white sleeve still casts something.
            let luminance = url.map { ImageCache.shared.luminance(for: $0) } ?? 0.5
            let darken = luminance * shadow.lightCompensation
            ZStack {
                if shadow.baseOpacity > 0 {
                    shape
                        .fill(.black.opacity(shadow.baseOpacity))
                        .frame(width: size * shadow.spread, height: size * shadow.spread)
                        .blur(radius: size * shadow.blur)
                        .offset(y: size * shadow.offsetY)
                }
                if shadow.opacity > 0 {
                    picture.resizable().aspectRatio(contentMode: .fill)
                        .frame(width: size * shadow.spread, height: size * shadow.spread)
                        .clipShape(shape)
                        .saturation(shadow.saturation)
                        .brightness(-darken)
                        .blur(radius: size * shadow.blur)
                        .opacity(shadow.opacity)
                        .offset(y: size * shadow.offsetY)
                }
            }
            // Flattened to one bitmap. Left as layers, the two blurs and the saturation are
            // compositor filters that the window server re-runs on every frame the row moves,
            // and a list of covers scrolled at a fraction of the refresh rate. The padding gives
            // the spill room before the flattening clips to its bounds: a cover's width each
            // way, since the blur runs well past the shadow's own edge and is pushed down too
            // (at half that, the bottom of every shadow was cut square).
            .padding(size)
            .drawingGroup()
            .padding(-size)
            .allowsHitTesting(false)
        }
    }

    private var placeholder: some View {
        shape
            .fill(.fill.quaternary)
            .overlay {
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.4))
                    .foregroundStyle(.tertiary)
            }
    }
}
