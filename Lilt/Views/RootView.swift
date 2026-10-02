import SwiftUI

struct RootView: View {
    @Environment(PlayerService.self) private var player
    @Environment(NavigationModel.self) private var navigation

    var body: some View {
        let mini = navigation.isMiniPlayer
        // The window never resizes. In mini only the platter is drawn, bottom-aligned where it
        // always sits; the rest of the window is fully transparent, and macOS hit-tests
        // non-opaque windows by their pixels, so clicks there fall through to whatever is behind.
        // The whole transition is one SwiftUI animation: column fades, glass shrinks to the platter.
        let radius = mini ? Theme.Radius.panel : Theme.Radius.window
        ZStack(alignment: .bottom) {
            // The window glass lives here, always mounted, so hiding it is explicit and reliable
            // (see GlassBackground). It fades with the column and is then switched off.
            GlassBackground(cornerRadius: Theme.Radius.window, isHidden: mini)
                .opacity(mini ? 0 : 1)
                .allowsHitTesting(false)
            if !mini {
                NavigationColumn()
                    .safeAreaBar(edge: .bottom, spacing: 0) {
                        if player.current != nil {
                            Color.clear.frame(height: navigation.platterHeight + Theme.Space.panelInset)
                        }
                    }
                    // Keeps the column solid to hit-testing (its glass pixels are transparent).
                    .background {
                        RoundedRectangle(cornerRadius: Theme.Radius.window, style: .continuous)
                            .fill(Color.black.opacity(0.012))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.window, style: .continuous))
                    .transition(.opacity)
            }
            if player.current != nil {
                NowPlayingBar()
                    .padding(.horizontal, mini ? 0 : Theme.Space.panelInset)
                    .padding(.bottom, mini ? 0 : Theme.Space.panelInset)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        // Expanded: the platter's drop shadow reaches the panel edge, so clip to the panel shape.
        // Mini: no outer clip at all. The platter's own glass shape is the only edge; a second
        // mask on the same curve rasterises it twice and leaves jagged corners.
        .mask {
            if mini {
                Rectangle().padding(-Theme.Size.shadowMargin)
            } else {
                RoundedRectangle(cornerRadius: Theme.Radius.window, style: .continuous)
            }
        }
        // Our own window shadow, drawn in the transparent margin around the visible shape.
        .background(alignment: .bottom) {
            PanelShadow(radius: radius, height: mini ? navigation.platterHeight : nil)
        }
        .padding(Theme.Size.shadowMargin)
        .animation(Theme.Motion.standard, value: player.current?.id)
        .animation(Theme.Motion.standard, value: mini)
    }
}

/// A soft shadow around the visible panel (or the platter in mini). Masked to the outside of
/// the shape so it never darkens the glass it belongs to.
private struct PanelShadow: View {
    let radius: CGFloat
    /// Height of the shape; nil fills the available height.
    let height: CGFloat?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let margin = Theme.Size.shadowMargin
        // The caster is exactly the panel shape; only its shadow reaches into the margin.
        shape
            .fill(.black)
            .frame(height: height)
            .frame(maxHeight: .infinity, alignment: .bottom)
            // Sized to stay inside the 36pt margin (blur extent + offset), so it never clips.
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.5 : 0.22), radius: 12, y: 5)
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.14), radius: 1.5, y: 0.5)
            // Keep everything in the margin, punch out the panel shape itself.
            .mask {
                ZStack {
                    Rectangle().padding(-margin)
                    shape
                        .frame(height: height)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
            }
            .allowsHitTesting(false)
    }
}

/// A stack of screens with a subtle horizontal hand-off. NavigationStack swaps views instantly
/// on macOS; here the search root stays alive underneath and pages ease in from the right by a
/// few points, fading, and back out the same way.
private struct NavigationColumn: View {
    @Environment(NavigationModel.self) private var navigation
    @Environment(ScrollTracker.self) private var scrollTracker

    /// How far a screen travels while entering or leaving.
    private static let travel: CGFloat = 20
    /// Softness at the far end of the hand-off. Off: blurring a full column of artwork every
    /// frame is what made the hand-off stutter. Slide and fade are cheap; this isn't.
    private static let blur: CGFloat = 0
    /// The outgoing screen gets out of the way faster than the incoming one arrives, so the two
    /// never read as a double exposure on the glass.
    private static let exit: Animation = .easeOut(duration: 0.12)
    private static let enter: Animation = .easeOut(duration: 0.2)

    var body: some View {
        let path = navigation.path
        ZStack {
            SearchScreen()
                .parked(path.isEmpty ? nil : .leading, travel: Self.travel, blur: Self.blur, animation: Self.exit, value: path)
            ForEach(Array(path.enumerated()), id: \.element.id) { index, item in
                let isTop = index == path.count - 1
                Group {
                    if item.kind == .library {
                        LibraryScreen()
                    } else {
                        BrowseScreen(item: item)
                    }
                }
                .parked(isTop ? nil : .leading, travel: Self.travel, blur: Self.blur, animation: Self.exit, value: path)
                .transition(.offset(x: Self.travel).combined(with: .opacity).animation(Self.enter))
            }
        }
        .animation(Self.enter, value: path)
        // The back button stays put while pages slide beneath it; it only fades in and out.
        .overlay(alignment: .topLeading) {
            if !path.isEmpty {
                BackButton()
                    .frame(height: Theme.Size.headerRow)
                    .padding(.top, Theme.Space.panelInset)
                    .padding(.leading, Theme.Space.panelInset)
                    .transition(.opacity.animation(Self.enter))
            }
        }
        .onChange(of: path.last?.id, initial: true) { _, top in
            scrollTracker.activeKey = top ?? ScrollTracker.searchKey
        }
    }
}

private struct BackButton: View {
    @Environment(NavigationModel.self) private var navigation

    var body: some View {
        Button {
            navigation.pop()
        } label: {
            Image(systemName: "chevron.left")
                .font(.body.weight(.semibold))
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(.pressable(scale: 0.88))
        .keyboardShortcut("[", modifiers: .command)
        .help("Back")
    }
}

private extension View {
    /// Keeps a screen mounted but slid aside and inert while another one is on top.
    @ViewBuilder
    func parked<V: Equatable>(_ edge: HorizontalEdge?, travel: CGFloat, blur: CGFloat, animation: Animation, value: V) -> some View {
        let parked = edge != nil
        self
            .offset(x: edge == .leading ? -travel : edge == .trailing ? travel : 0)
            .blur(radius: parked ? blur : 0)
            // Fade the screen as one flattened layer rather than row by row.
            .compositingGroup()
            .opacity(parked ? 0 : 1)
            .animation(animation, value: value)
            .allowsHitTesting(!parked)
            .accessibilityHidden(parked)
    }
}
