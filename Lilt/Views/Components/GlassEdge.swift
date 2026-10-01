import SwiftUI

/// The rim of a piece of glass: a hairline that catches light along the top and falls off to a
/// faint dark line at the bottom. Drawn just outside the shape so it never eats into the glass.
struct GlassEdge<S: InsettableShape>: ViewModifier {
    let shape: S
    var opacity: Double = 1

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.overlay {
            shape.inset(by: -0.5).stroke(
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(colorScheme == .dark ? 0.45 : 0.9), location: 0),
                        .init(color: .white.opacity(colorScheme == .dark ? 0.12 : 0.35), location: 0.45),
                        .init(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.10), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 1
            )
            .opacity(opacity)
            .allowsHitTesting(false)
        }
    }
}

extension View {
    func glassEdge<S: InsettableShape>(_ shape: S, opacity: Double = 1) -> some View {
        modifier(GlassEdge(shape: shape, opacity: opacity))
    }
}
