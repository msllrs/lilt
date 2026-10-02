import SwiftUI

struct RootView: View {
    @Environment(PlayerService.self) private var player
    @Environment(NavigationModel.self) private var navigation
    /// The panel's full height, so the container animates between two real numbers (a jump to
    /// "fill" can't interpolate, and the clip would snap open ahead of the glass).
    @State private var fullHeight: CGFloat = 0
    /// The column's height while expanded. In mini the window is only as tall as the platter, so
    /// the (invisible) column keeps this size instead of reflowing, and reports none of it.
    @State private var columnHeight: CGFloat = 0

    var body: some View {
        let mini = navigation.isMiniPlayer
        // Collapsing to the mini player is one bottom-anchored animation: the container (glass,
        // shadow and the clip on the column) shrinks from the full panel to the platter while the
        // column fades inside it; expanding is the exact reverse. The window frame itself changes
        // unanimated around this (see AppDelegate), while the region being added or removed is
        // transparent. The column stays mounted throughout so nothing reloads on the way back.
        let radius = mini ? Theme.Radius.panel : Theme.Radius.window
        let inset = Theme.Space.panelInset
        // The container ends flush with the platter's top; the platter keeps its bottom inset so
        // it never moves vertically, while it widens to the full panel as before.
        let containerHeight: CGFloat? = mini ? navigation.platterHeight + inset : (fullHeight > 0 ? fullHeight : nil)
        ZStack(alignment: .bottom) {
            // The window glass lives here, always mounted, so hiding it is explicit and reliable
            // (see GlassBackground). It shrinks and fades with the collapse, then is switched off.
            GlassBackground(cornerRadius: Theme.Radius.window, isHidden: mini)
                .frame(maxHeight: containerHeight ?? .infinity)
                .opacity(mini ? 0 : 1)
                .allowsHitTesting(false)
            NavigationColumn()
                .safeAreaBar(edge: .bottom, spacing: 0) {
                    if player.current != nil {
                        Color.clear.frame(height: navigation.platterHeight + Theme.Space.panelInset)
                    }
                }
                // Keeps the column solid to hit-testing (its glass pixels are transparent).
                // Inset by a point so its antialiased edge never shows beyond the glass.
                .background {
                    RoundedRectangle(cornerRadius: Theme.Radius.window - 1, style: .continuous)
                        .fill(Color.black.opacity(0.012))
                        .padding(1)
                }
                // Clipped to the container, so a shrinking container cuts the content off rather
                // than leaving it hanging in the air. Fully transparent in mini: nothing to see,
                // and transparent pixels pass clicks through to the window behind.
                .mask(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: Theme.Radius.window, style: .continuous)
                        .frame(maxHeight: containerHeight ?? .infinity)
                }
                .opacity(mini ? 0 : 1)
                .allowsHitTesting(!mini)
                // In mini the window is shorter than the column's minimum; laid out at its
                // expanded size but reporting zero height, it can't push the platter down.
                .frame(height: mini && columnHeight > 0 ? columnHeight : nil)
                .frame(height: mini ? 0 : nil, alignment: .bottom)
            if player.current != nil {
                // The bottom inset is constant so the platter never shifts vertically.
                NowPlayingBar()
                    .padding(.horizontal, mini ? 0 : inset)
                    .padding(.bottom, inset)
                    // Expanded: the platter's drop shadow would spill past the panel; keep it in.
                    .mask {
                        if mini {
                            Rectangle().padding(-Theme.Size.shadowMargin)
                        } else {
                            RoundedRectangle(cornerRadius: Theme.Radius.window, style: .continuous)
                                .frame(maxHeight: .infinity)
                                .padding(.top, -2000)
                        }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if !mini {
                // The window's real edges are out in the shadow margin, so resizing happens here.
                ResizeEdges()
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
            fullHeight = height
            if !navigation.isMiniPlayer { columnHeight = height }
        }
        // Our own window shadow, drawn in the transparent margin around the visible shape.
        .background(alignment: .bottom) {
            PanelShadow(radius: radius, height: mini ? navigation.platterHeight : containerHeight, bottomInset: mini ? inset : 0)
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
    /// Inset from the bottom (the platter's, in mini).
    var bottomInset: CGFloat = 0

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let margin = Theme.Size.shadowMargin
        // The caster is exactly the panel shape; only its shadow reaches into the margin.
        shape
            .fill(.black)
            .frame(height: height)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, bottomInset)
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
                        .padding(.bottom, bottomInset)
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
