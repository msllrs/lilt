import SwiftUI

/// The rim of a piece of glass: a hairline that catches light along the top and falls off to a
/// faint dark line at the bottom. Drawn just outside the shape so it never eats into the glass.
struct GlassEdge<S: InsettableShape>: ViewModifier {
    let shape: S
    var opacity: Double = 1
    /// A colour cast onto the lit top edge, e.g. from artwork sitting above the glass.
    var cast: Color? = nil
    /// How much of `cast` goes into the highlight (0 = plain white).
    var castMix: Double = 0.5
    /// Softens the rim into a glow.
    var blur: Double = 0
    var blend: BlendMode = .normal

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// The rim's strengths for the window style on screen, in this appearance.
    private var edge: SurfaceStyle.Edge { ArtworkStyle.shared.surface(colorScheme, reduceTransparency: reduceTransparency).glassEdge }
    /// Where the highlight hands over to the fainter middle of the rim.
    private static var middleLocation: Double { 0.45 }

    func body(content: Content) -> some View {
        let edge = edge
        content.overlay {
            shape.inset(by: -0.5).stroke(
                LinearGradient(
                    stops: [
                        .init(color: topColor(edge), location: 0),
                        .init(color: .white.opacity(edge.middleOpacity), location: Self.middleLocation),
                        .init(color: .black.opacity(edge.bottomOpacity), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: edge.lineWidth + blur * 0.5
            )
            .blur(radius: blur)
            .blendMode(blend)
            .opacity(opacity)
            .allowsHitTesting(false)
        }
    }

    private func topColor(_ edge: SurfaceStyle.Edge) -> Color {
        let white = Color.white.opacity(edge.topOpacity)
        guard let cast else { return white }
        // The cast reads strongest right where the highlight is.
        return white.mix(with: cast, by: castMix)
    }
}

extension View {
    func glassEdge<S: InsettableShape>(_ shape: S, opacity: Double = 1, cast: Color? = nil, castMix: Double = 0.5, blur: Double = 0, blend: BlendMode = .normal) -> some View {
        modifier(GlassEdge(shape: shape, opacity: opacity, cast: cast, castMix: castMix, blur: blur, blend: blend))
    }
}
