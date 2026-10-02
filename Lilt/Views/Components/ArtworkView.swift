import SwiftUI

/// Album/artist artwork with a Sleeve-style finish: a spotlight from the top, a hairline inset
/// border and an ambient shadow in the artwork's own colours. Images come from `ImageCache`, so
/// revisiting a row never flashes a placeholder, and a smaller cached rendition stands in,
/// blurred, while a larger one loads.
struct ArtworkView: View {
    let url: URL?
    let size: CGFloat
    let radius: CGFloat
    /// Picks the shadow preset (rows, player, pages).
    var context: ArtworkContext = .row
    /// Spins the picture inside the sleeve; the lighting, keyline and shadow stay put.
    var rotation: Angle = .zero

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @State private var image: NSImage?
    /// True while `image` is a stand-in rendition at another size.
    @State private var isStandIn = false

    init(url: URL?, size: CGFloat, radius: CGFloat, context: ArtworkContext = .row, rotation: Angle = .zero) {
        self.url = url
        self.size = size
        self.radius = radius
        self.context = context
        self.rotation = rotation
        // Seed synchronously so a cache hit renders on the first frame.
        let seed = MainActor.assumeIsolated { () -> (NSImage?, Bool) in
            guard let url else { return (nil, false) }
            if let hit = ImageCache.shared.cached(url) { return (hit, false) }
            if let variant = ImageCache.shared.anyVariant(for: url) { return (variant, true) }
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
                sleeve(Image(nsImage: image))
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

    private func sleeve(_ picture: Image) -> some View {
        picture.resizable().aspectRatio(contentMode: .fill)
            .frame(width: size, height: size)
            // A genuinely undersized stand-in is blurred to hide the resampling until the real
            // one lands; a near-enough one is shown as is.
            .blur(radius: standInBlur)
            .rotationEffect(rotation)
            .overlay(spotlight)
            .clipShape(shape)
            .overlay(insetKeyline)
            .overlay(outerSeparator)
            .background { ambientShadow(picture) }
            .animation(Theme.Motion.quick, value: isStandIn)
    }

    private func load() async {
        guard let url else { image = nil; return }
        if let hit = ImageCache.shared.cached(url) {
            image = hit
            isStandIn = false
            return
        }
        if let variant = ImageCache.shared.anyVariant(for: url) {
            image = variant
            isStandIn = true
        } else if image != nil {
            // Nothing cached for the new URL: keep the previous picture, blurred, rather than
            // dropping to the placeholder while the real one loads.
            isStandIn = true
        }
        guard let loaded = await ImageCache.shared.load(url), !Task.isCancelled else { return }
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
