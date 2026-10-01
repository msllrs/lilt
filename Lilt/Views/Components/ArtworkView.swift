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

    @Environment(\.colorScheme) private var colorScheme
    @State private var image: NSImage?
    /// True while `image` is a stand-in rendition at another size.
    @State private var isStandIn = false

    init(url: URL?, size: CGFloat, radius: CGFloat, context: ArtworkContext = .row) {
        self.url = url
        self.size = size
        self.radius = radius
        self.context = context
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

    private var style: ArtworkStyle { .shared }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: radius, style: .continuous) }

    /// The inset edge is drawn dark on light backgrounds and light on dark ones.
    private var borderTint: Color { colorScheme == .dark ? .white : .black }

    var body: some View {
        Group {
            if let image {
                sleeve(Image(nsImage: image))
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .task(id: url) { await load() }
    }

    private func sleeve(_ picture: Image) -> some View {
        picture.resizable().aspectRatio(contentMode: .fill)
            .frame(width: size, height: size)
            // A stand-in is a different size; blur hides the resampling until the real one lands.
            .blur(radius: isStandIn ? size * 0.12 : 0)
            .overlay(spotlight)
            .overlay(insetBorder)
            .clipShape(shape)
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

    /// A uniform hairline inner edge on all sides, so the artwork reads as a physical sleeve
    /// rather than a flat rectangle.
    private var insetBorder: some View {
        shape.strokeBorder(borderTint.opacity(style.borderOpacity), lineWidth: style.borderWidth)
            .blendMode(style.borderBlend.blendMode)
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
