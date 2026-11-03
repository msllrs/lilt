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
    /// This glass's share of the surface's dark bottom line (1: all of it).
    var bottomScale: Double = 1

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// The rim's strengths for the window style on screen, in this appearance.
    private var edge: SurfaceStyle.Edge { ArtworkStyle.shared.surface(colorScheme, reduceTransparency: reduceTransparency).glassEdge }
    /// Where the highlight hands over to the fainter middle of the rim.
    private static var middleLocation: Double { 0.45 }

    func body(content: Content) -> some View {
        let edge = edge
        content.overlay {
            Group {
                if edge.hairline {
                    // An even hairline that lightens dark glass and darkens light glass, rather
                    // than a lit top and a shadowed bottom.
                    let hairline = Self.hairline(edge, dark: colorScheme == .dark)
                    shape.inset(by: -edge.hairlineWidth / 2)
                        .stroke(cast.map { hairline.color.mix(with: $0, by: castMix) } ?? hairline.color, lineWidth: edge.hairlineWidth + blur * 0.5)
                        .blur(radius: blur)
                        .blendMode(hairline.blend)
                } else {
                    shape.inset(by: -0.5).stroke(
                        LinearGradient(
                            stops: [
                                .init(color: topColor(edge), location: 0),
                                .init(color: .white.opacity(edge.middleOpacity), location: Self.middleLocation),
                                .init(color: .black.opacity(Self.bottomOpacity(edge.bottomOpacity, scale: bottomScale)), location: 1),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: edge.lineWidth + blur * 0.5
                    )
                    .blur(radius: blur)
                    .blendMode(blend)
                }
            }
            .opacity(opacity)
            .allowsHitTesting(false)
        }
    }

    /// The hairline's colour and blend: white added as light on dark glass, black multiplied
    /// down on light glass (white under plus-darker would leave it untouched).
    static func hairline(_ edge: SurfaceStyle.Edge, dark: Bool) -> (color: Color, blend: BlendMode) {
        dark ? (Color.white.opacity(edge.hairlineOpacity), .plusLighter) : (Color.black.opacity(edge.hairlineOpacity), .plusDarker)
    }

    /// The dark bottom line's opacity for glass taking `scale` of the surface's.
    static func bottomOpacity(_ surface: Double, scale: Double) -> Double { surface * scale }

    private func topColor(_ edge: SurfaceStyle.Edge) -> Color {
        let white = Color.white.opacity(edge.topOpacity)
        guard let cast else { return white }
        // The cast reads strongest right where the highlight is.
        return white.mix(with: cast, by: castMix)
    }
}

extension View {
    func glassEdge<S: InsettableShape>(_ shape: S, opacity: Double = 1, cast: Color? = nil, castMix: Double = 0.5, blur: Double = 0, blend: BlendMode = .normal, bottomScale: Double = 1) -> some View {
        modifier(GlassEdge(shape: shape, opacity: opacity, cast: cast, castMix: castMix, blur: blur, blend: blend, bottomScale: bottomScale))
    }
}
