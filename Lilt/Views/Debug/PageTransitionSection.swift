#if DEBUG
import SwiftUI

/// The tweak panel's Page transition section: which hand-off pages use, and its dials. Each
/// variant keeps its own dials; only the ones it reads are shown. Slow it down with Motion ▸
/// Animation speed to watch a hand-off frame by frame.
struct PageTransitionSection: View {
    @State private var settings = PageTransitionSettings.shared

    var body: some View {
        @Bindable var settings = settings
        let transition = settings.transition
        Section {
            Picker("Variant", selection: $settings.transition) {
                ForEach(PageTransition.allCases) { Text($0.title).tag($0) }
            }
            ForEach(PageTransitionDials.Dial.allCases.filter { transition.dials.contains($0) }, id: \.self) { dial in
                slider(label(dial, for: transition), binding(dial, for: transition), PageTransitionDials.ranges[dial]!)
            }
            if transition != .current {
                Button("Reset \(transition.title)") { settings.resetDials(for: transition) }
            }
        } header: {
            Text("Page transition")
        } footer: {
            Text(footer(for: transition))
        }
    }

    private func binding(_ dial: PageTransitionDials.Dial, for transition: PageTransition) -> Binding<Double> {
        Binding(
            get: { settings.dials(for: transition)[dial] },
            set: { value in
                var dials = settings.dials(for: transition)
                dials[dial] = value
                settings.setDials(dials, for: transition)
            }
        )
    }

    /// What each dial moves in this variant.
    private func label(_ dial: PageTransitionDials.Dial, for transition: PageTransition) -> String {
        switch (transition, dial) {
        case (.heroMorph, .duration): "Flight (s)"
        case (.staggered, .duration): "Each piece (s)"
        case (.maskedWipe, .duration): "Sweep (s)"
        case (_, .duration): "Arrival (s)"
        case (.pushParallax, .travel): "Travel (pt)"
        case (.maskedWipe, .travel): "Drift (pt)"
        case (.heroMorph, .travel), (.staggered, .travel): "Rise (pt)"
        case (_, .travel): "Nudge (pt)"
        case (.heroMorph, .stagger), (.staggered, .stagger): "Row stagger (s)"
        case (_, .stagger): "Arrival delay (s)"
        case (.pushParallax, .scale): "Beneath: shrink"
        case (_, .scale): "Scale step"
        case (.maskedWipe, .blur): "Soft edge (pt)"
        case (_, .blur): "Blur (pt)"
        }
    }

    private func footer(for transition: PageTransition) -> String {
        switch transition {
        case .current: "The hand-off as it ships: Theme.Motion pageExit, pageEnter and pageTravel. The two pages overlap."
        case .sequencedFade: "Out in 0.09s, nudged back by two thirds of the nudge; in after the delay on a spring, never both at once."
        case .pushParallax: "The page beneath moves 30% of the travel and is dimmed within 0.1s; the arriving page fades in from the delay."
        case .scaleDepth: "Out in 0.1s to 1 − step; in from 1 + step on a spring after the delay. Scaled from the top edge."
        case .heroMorph: "The tapped row's cover flies to the hero (and back on pop while the row is on screen); title, buttons and rows follow."
        case .staggered: "Hero, title, buttons, then rows one by one (capped at 12); the old page fades out in 0.09s."
        case .blurCut: "Blur follows the fade: strongest as a page all but disappears, none once it has settled. Blur costs GPU time."
        case .maskedWipe: "A soft edge sweeps trailing to leading on push, back on pop; each point shows one page only."
        }
    }

    private func slider(_ label: String, _ value: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
        LabeledContent(label) {
            HStack(spacing: Theme.Space.sm) {
                Slider(value: value, in: range)
                Text(String(format: range.upperBound > 10 ? "%.0f" : "%.3f", value.wrappedValue))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
            }
        }
    }
}
#endif
