import SwiftUI

/// Where the panel's notices appear: the current one, swapping quickly for the next. Lays out
/// as nothing while there is none, so it never takes a click meant for what's beneath.
struct NoticeHost: View {
    @Environment(NoticeCenter.self) private var center
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let notice = center.current {
                NoticeCapsule(notice: notice)
                    // Keyed by notice, so a replacement transitions out and in rather than
                    // rewriting the one that's up.
                    .id(notice.id)
                    .transition(transition)
            }
        }
        .animation(reduceMotion ? Theme.Motion.quick : Theme.Motion.standard, value: center.current?.id)
    }

    /// Rises a few points into place and sinks back out; with Reduce Motion it only fades.
    private var transition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .offset(y: Theme.Space.sm).combined(with: .scale(scale: 0.96, anchor: .bottom)).combined(with: .opacity),
            removal: .scale(scale: 0.96, anchor: .bottom).combined(with: .opacity)
        )
    }
}

/// One notice: a small glass capsule with a cover or symbol, a line of text, the action (with
/// its shortcut), and a ring that empties as the notice's time runs out. Clicking it or swiping
/// it away dismisses it; resting the pointer on it holds the countdown.
struct NoticeCapsule: View {
    let notice: Notice
    @Environment(NoticeCenter.self) private var center
    @Environment(\.screenIsParked) private var parked
    @State private var isHovering = false
    /// How far it has been dragged, while being swiped.
    @State private var drag: CGSize = .zero

    private static let font: Font = .callout
    /// Height of the button inside, and of the artwork: the capsule's padding around them keeps
    /// the button's ends concentric with the capsule's.
    private static let inner = Theme.Size.noticeArtwork
    /// How far a swipe must travel before it counts, rather than springing back.
    private static let swipeDistance: CGFloat = 32

    var body: some View {
        HStack(spacing: Theme.Space.sm) {
            // A symbol sits closer to its line than a cover does: it has no edge of its own, so
            // the cover's gap leaves it looking adrift.
            HStack(spacing: isSymbol ? Theme.Space.xs : Theme.Space.sm) {
                icon
                message
            }
            if let action = notice.action { button(action) }
            ring
        }
        .padding(Theme.Space.sm)
        .background {
            // As the platter's glass: regular, so the line reads over the rows passing behind.
            Color.clear.glassEffect(.regular, in: Capsule())
                .allowsHitTesting(false)
        }
        .glassEdge(Capsule())
        // Glass pixels are transparent to the window server; this keeps the capsule clickable.
        .background { Capsule().fill(Color.black.opacity(0.012)) }
        .contentShape(Capsule())
        .offset(x: drag.width, y: max(drag.height, 0) + min(drag.height, 0) * 0.2)
        .onTapGesture { center.dismiss(notice.id) }
        .gesture(swipe)
        .onHover { hovering in
            isHovering = hovering
            center.setHovering(hovering)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(notice.message)
        .onAppear { AccessibilityNotification.Announcement(notice.message).post() }
    }

    private var isSymbol: Bool {
        if case .symbol = notice.icon { return true }
        return false
    }

    @ViewBuilder
    private var icon: some View {
        switch notice.icon {
        case .artwork(let url):
            ArtworkView(url: url, size: Self.inner, radius: Theme.Radius.artwork(Self.inner))
        case .symbol(let name):
            Image(systemName: name)
                .font(Self.font.weight(.semibold))
                .foregroundStyle(.secondary)
                // Only as wide as the glyph, centred on the cover's height; inset from the end
                // so it sits where a cover's middle would.
                .frame(height: Self.inner)
                .padding(.leading, Theme.Space.xs)
        case nil:
            EmptyView()
        }
    }

    /// As wide as the text needs and no wider (the hidden copy sizes the slot), down to what
    /// the panel allows; a longer line scrolls while the pointer rests on it.
    private var message: some View {
        Text(notice.message).font(Self.font).lineLimit(1).hidden()
            .overlay { MarqueeText(text: notice.message, isActive: isHovering, font: Self.font) }
            .padding(.leading, notice.icon == nil ? Theme.Space.xs : 0)
    }

    private func button(_ action: Notice.Action) -> some View {
        Button {
            center.performAction()
        } label: {
            HStack(spacing: Theme.Space.xs) {
                Text(action.title).font(Self.font.weight(.semibold))
                Text(action.shortcutLabel).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, Theme.Space.sm)
            .frame(height: Self.inner)
            .background(.fill.tertiary, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.pressable(scale: 0.94))
        .fixedSize()
        .help("\(action.title) (\(action.shortcutLabel))")
    }

    /// Empties clockwise as the time runs out; holds while the countdown does.
    private var ring: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: center.isPaused || parked)) { _ in
            let remaining = center.remainingFraction
            ZStack {
                Circle().stroke(.quaternary, lineWidth: 2)
                Circle()
                    .trim(from: 0, to: remaining)
                    .stroke(.secondary, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: Theme.Size.controlIcon, height: Theme.Size.controlIcon)
        .padding(.trailing, Theme.Space.xs)
        .accessibilityHidden(true)
    }

    /// Follows the pointer sideways or down (barely up); far enough, or flung, and it's gone.
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { drag = $0.translation }
            .onEnded { value in
                let travel = value.predictedEndTranslation
                if abs(travel.width) > Self.swipeDistance || travel.height > Self.swipeDistance {
                    center.dismiss(notice.id)
                } else {
                    withAnimation(Theme.Motion.standard) { drag = .zero }
                }
            }
    }
}
