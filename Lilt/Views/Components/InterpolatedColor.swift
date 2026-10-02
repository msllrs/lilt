import AppKit
import SwiftUI

/// Hands its content a colour that slides from one value to the next (`Theme.Motion.cast`).
/// `Color` itself isn't animatable, so a change of cast would cut from one song's colour to the
/// next. The animation is scoped to this view alone: putting it on a whole surface made every
/// other change there (an artwork swap, say) crossfade over 0.8s as well.
struct InterpolatedColor<Content: View>: View {
    private let color: Color?
    private let content: (Color?) -> Content

    init(_ color: Color?, @ViewBuilder content: @escaping (Color?) -> Content) {
        self.color = color
        self.content = content
    }

    var body: some View {
        ColorInterpolator(color, content: content)
            .animation(Theme.Motion.cast, value: color)
    }
}

/// The animatable core: its data is the colour's components, and every frame of an animation
/// re-renders the content with the in-between colour. Nil fades through transparency.
nonisolated private struct ColorInterpolator<Content: View>: View, Animatable {
    private var components: AnimatablePair<AnimatablePair<Double, Double>, AnimatablePair<Double, Double>>
    private let content: (Color?) -> Content

    init(_ color: Color?, @ViewBuilder content: @escaping (Color?) -> Content) {
        let c = color.flatMap { NSColor($0).usingColorSpace(.sRGB) }
        components = AnimatablePair(
            AnimatablePair(c.map { Double($0.redComponent) } ?? 0, c.map { Double($0.greenComponent) } ?? 0),
            AnimatablePair(c.map { Double($0.blueComponent) } ?? 0, c == nil ? 0 : Double(c!.alphaComponent))
        )
        self.content = content
    }

    var animatableData: AnimatablePair<AnimatablePair<Double, Double>, AnimatablePair<Double, Double>> {
        get { components }
        set { components = newValue }
    }

    var body: some View {
        let alpha = components.second.second
        content(alpha > 0.001 ? Color(.sRGB, red: components.first.first, green: components.first.second, blue: components.second.first, opacity: alpha) : nil)
    }
}
