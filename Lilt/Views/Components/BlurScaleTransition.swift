import SwiftUI

/// A glyph swap: the outgoing symbol shrinks, blurs and fades while the incoming one grows in
/// from small and sharpens.
struct BlurScaleTransition: Transition {
    var scale: CGFloat = 0.5
    var blur: CGFloat = 6

    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .scaleEffect(phase.isIdentity ? 1 : scale)
            .blur(radius: phase.isIdentity ? 0 : blur)
            .opacity(phase.isIdentity ? 1 : 0)
    }
}

extension AnyTransition {
    static var blurScale: AnyTransition { AnyTransition(BlurScaleTransition()) }
}
