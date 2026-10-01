import SwiftUI

/// Album/artist artwork with a Sleeve-style finish: a soft spotlight from the top-left and a
/// hairline inset border, both blended so they take on the artwork's own colours.
struct ArtworkView: View {
    let url: URL?
    let size: CGFloat
    let radius: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: radius, style: .continuous) }

    /// The inset edge is drawn dark on light backgrounds and light on dark ones.
    private var borderTint: Color { colorScheme == .dark ? .white : .black }

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().aspectRatio(contentMode: .fill)
                    .overlay(spotlight)
                    .overlay(insetBorder)
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
    }

    private var style: ArtworkStyle { .shared }

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

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(.fill.quaternary)
            .overlay {
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.4))
                    .foregroundStyle(.tertiary)
            }
    }
}
