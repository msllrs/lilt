import AppKit
import SwiftUI

/// Hands its content a colour that slides from one value to the next (`Theme.Motion.cast`).
/// `Color` itself isn't animatable, so a change of cast would cut from one song's colour to the
/// next. The interpolation runs in a hidden sibling and reaches the content through a
/// preference, so the content is never inside the 0.8s transaction: a title or cover changing at
/// the same moment keeps its own timing instead of inheriting the slow crossfade.
struct InterpolatedColor<Content: View>: View {
    private let color: Color?
    private let content: (Color?) -> Content
    @State private var shown: Color?

    init(_ color: Color?, @ViewBuilder content: @escaping (Color?) -> Content) {
        self.color = color
        self.content = content
    }

    var body: some View {
        content(shown ?? color)
            .background {
                ColorInterpolator(color)
                    .animation(Theme.Motion.cast, value: color)
                    .onPreferenceChange(InterpolatedColorKey.self) { value in
                        MainActor.assumeIsolated { shown = value }
                    }
            }
    }
}

private struct InterpolatedColorKey: PreferenceKey {
    static let defaultValue: Color? = nil
    static func reduce(value: inout Color?, nextValue: () -> Color?) { value = nextValue() ?? value }
}

/// The animatable core: its data is the colour's components, and every frame of an animation
/// publishes the in-between colour. Nil fades through transparency.
nonisolated private struct ColorInterpolator: View, Animatable {
    private var components: AnimatablePair<AnimatablePair<Double, Double>, AnimatablePair<Double, Double>>

    init(_ color: Color?) {
        let c = color.flatMap { NSColor($0).usingColorSpace(.sRGB) }
        components = AnimatablePair(
            AnimatablePair(c.map { Double($0.redComponent) } ?? 0, c.map { Double($0.greenComponent) } ?? 0),
            AnimatablePair(c.map { Double($0.blueComponent) } ?? 0, c == nil ? 0 : Double(c!.alphaComponent))
        )
    }

    var animatableData: AnimatablePair<AnimatablePair<Double, Double>, AnimatablePair<Double, Double>> {
        get { components }
        set { components = newValue }
    }

    var body: some View {
        let alpha = components.second.second
        Color.clear.preference(
            key: InterpolatedColorKey.self,
            value: alpha > 0.001 ? Color(.sRGB, red: components.first.first, green: components.first.second, blue: components.second.first, opacity: alpha) : nil
        )
    }
}
