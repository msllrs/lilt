import SwiftUI

/// Album/artist artwork with a Sleeve-style finish: a soft spotlight from the top-left and a
/// hairline inset border, both blended so they take on the artwork's own colours.
struct ArtworkView: View {
    let url: URL?
    let size: CGFloat
    let radius: CGFloat

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: radius, style: .continuous) }

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

    /// Light falling from the top-left, fading out before the middle. `plusLighter` lifts the
    /// artwork's own hues instead of washing them out with white.
    private var spotlight: some View {
        LinearGradient(
            stops: [
                .init(color: .white.opacity(0.22), location: 0),
                .init(color: .white.opacity(0.06), location: 0.35),
                .init(color: .clear, location: 0.65),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .blendMode(.plusLighter)
    }

    /// A one-pixel inner edge, brighter where the light hits, so the artwork reads as a physical
    /// sleeve rather than a flat rectangle.
    private var insetBorder: some View {
        shape.strokeBorder(
            LinearGradient(
                colors: [.white.opacity(0.45), .white.opacity(0.12), .white.opacity(0.05)],
                startPoint: .top,
                endPoint: .bottom
            ),
            lineWidth: 1
        )
        .blendMode(.overlay)
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
