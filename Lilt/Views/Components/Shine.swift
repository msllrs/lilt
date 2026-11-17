import SwiftUI

/// What asks a row to shine: each `fire()` is one sweep. A row keeps one in its own state and
/// notes every menu action through it, so the ones that confirm themselves with a sweep do so
/// once each, from the row they were picked on.
struct ShineTrigger: Equatable {
    private(set) var count = 0

    mutating func fire() { count += 1 }

    /// Copy Link, Play Next and Add to Queue leave nothing to see on the row itself, so the row
    /// shines as the notice comes up. The rest change something you can see already (a like,
    /// a removal, a page opening) or play.
    static func shines(after action: RowAction) -> Bool {
        switch action {
        case .copyLink, .playNext, .addToQueue: true
        default: false
        }
    }

    /// Fires if `action` is one that shines.
    mutating func note(_ action: RowAction) {
        if Self.shines(after: action) { fire() }
    }
}

extension View {
    /// One soft band of light across this view, leading edge to trailing, each time `trigger`
    /// fires, clipped to `shape` (the row's highlight). Added light in dark mode, a gentle
    /// overlay in light mode; none at all under Reduce Motion. Drawn over the row without
    /// taking part in its layout or its clicks. Dials in `ShineStyle`.
    func shine(trigger: ShineTrigger, in shape: some Shape) -> some View {
        modifier(ShineModifier(trigger: trigger.count, shape: shape))
    }
}

/// Nothing but an empty overlay until the row first shines: every row in a list carries one, and
/// few ever fire it.
private struct ShineModifier<S: Shape>: ViewModifier {
    let trigger: Int
    let shape: S

    func body(content: Content) -> some View {
        content.overlay {
            if trigger > 0 { ShineSweeps(trigger: trigger, shape: shape).allowsHitTesting(false) }
        }
    }
}

/// A row's sweeps, from its first: arriving with a trigger already fired, it sweeps for that one.
private struct ShineSweeps<S: Shape>: View {
    let trigger: Int
    let shape: S

    @Environment(\.colorScheme) private var colorScheme
    /// The sweep under way, by trigger count; nil at rest, when nothing is drawn.
    @State private var sweep: Int?

    var body: some View {
        #if DEBUG
        let _ = RowBuildCounts.notePart("shine")
        #endif
        Color.clear
            .overlay {
                if let sweep {
                    ShineBand(style: ArtworkStyle.shared.shine) {
                        // A newer sweep replaced this one; it clears itself.
                        if self.sweep == sweep { self.sweep = nil }
                    }
                    .id(sweep)
                    .clipShape(shape)
                    // Outside the clip, so the band blends with the row beneath it rather than
                    // with the clip's own clear layer.
                    .blendMode(colorScheme == .dark ? .plusLighter : .overlay)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .onChange(of: trigger, initial: true) { _, count in
                guard Theme.Motion.shine(ArtworkStyle.shared.shine) != nil else { return }
                sweep = count
            }
    }
}

/// The band: in at the leading edge on appearing, out past the trailing one, then `done`.
private struct ShineBand: View {
    let style: ShineStyle
    let done: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    /// 0 with the band just outside the leading edge, 1 just past the trailing one.
    @State private var progress: CGFloat = 0

    var body: some View {
        let peak = colorScheme == .dark ? style.darkOpacity : style.lightOpacity
        GeometryReader { proxy in
            let width = proxy.size.width * style.band
            LinearGradient(
                colors: [.white.opacity(0), .white.opacity(peak), .white.opacity(0)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: width, height: proxy.size.height)
            .offset(x: -width + (proxy.size.width + width) * progress)
        }
        .onAppear {
            guard let sweep = Theme.Motion.shine(style) else { return done() }
            withAnimation(sweep) { progress = 1 } completion: { done() }
        }
    }
}
