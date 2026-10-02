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

    func body(content: Content) -> some View {
        content.overlay {
            shape.inset(by: -0.5).stroke(
                LinearGradient(
                    stops: [
                        .init(color: topColor, location: 0),
                        .init(color: .white.opacity(colorScheme == .dark ? 0.12 : 0.35), location: 0.45),
                        .init(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.10), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 1 + blur * 0.5
            )
            .blur(radius: blur)
            .blendMode(blend)
            .opacity(opacity)
            .allowsHitTesting(false)
        }
    }

    private var topColor: Color {
        let white = Color.white.opacity(colorScheme == .dark ? 0.45 : 0.9)
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
