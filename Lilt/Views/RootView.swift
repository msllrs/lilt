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

    /// Our clips follow the panel shape (the native frame's corner is set to the same radius).
    private static let clipRadius: CGFloat = Theme.Radius.window
    #if NATIVE_FRAME
    private static let miniAnimation: Animation = Theme.Motion.frame
    private static let surfaceHidesInMini = false
    #else
    private static let miniAnimation: Animation = Theme.Motion.standard
    private static let surfaceHidesInMini = true
    #endif

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
        #if NATIVE_FRAME
        // The window itself is the container (its frame animates, see AppDelegate), so our
        // surfaces and clips just fill it. A column that has never been laid out expanded
        // (launched in mini) holds the height the window is heading for.
        let containerHeight: CGFloat? = nil
        // Held only while the frame animates or in mini, when the hosting view is pinned at the
        // expanded height. While expanded and idle the column just fills the view: a fixed height
        // fed back from the view's own measurement runs a frame behind a live resize, overflows,
        // and an overflowing stack is centred, cutting the header and the platter.
        let holdsExpandedLayout = mini || navigation.isFrameAnimating
        let heldHeight = columnHeight > 0 ? columnHeight : navigation.expandedFrameHeight
        let platterBottomInset: CGFloat = mini ? 0 : inset
        #else
        let containerHeight: CGFloat? = mini ? navigation.platterHeight + inset : (fullHeight > 0 ? fullHeight : nil)
        let holdsExpandedLayout = mini
        let heldHeight = columnHeight
        let platterBottomInset = inset
        #endif
        ZStack(alignment: .bottom) {
            // The panel's surface lives here, always mounted, so hiding it is explicit and reliable
            // (see PanelBackground). It shrinks and fades with the collapse, then is switched off.
            // Under the native frame the surface never fades or resizes: it stays at the expanded
            // height, bottom-anchored like the column, and the window's own frame reveals or hides
            // it. Sized by SwiftUI it would lag the window by a layout pass, leaving rows hanging
            // above its top edge for a frame; in mini the platter sits on it as when expanded.
            // It hangs from an overlay so its extra height never enters the stack's layout: an
            // oversized stack gets centred, which would push the platter below the window.
            Color.clear
                .overlay(alignment: .bottom) {
                    PanelBackground(cornerRadius: Theme.Radius.window, isHidden: Self.surfaceHidesInMini && mini)
                        .frame(maxHeight: containerHeight ?? .infinity)
                        .frame(height: Self.surfaceHidesInMini || heldHeight <= 0 ? nil : heldHeight)
                        .opacity(Self.surfaceHidesInMini && mini ? 0 : 1)
                }
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
                // Native frame: none of this. The window clips and reveals the column, and a masked
                // or fading column animating beneath the platter is rendered as an offscreen
                // group that lands above the platter's glass, so rows showed through it mid-move.
                .modifier(ColumnClip(containerHeight: containerHeight))
                // Fades with the move in both builds; in mini it would otherwise still be there
                // behind the platter's glass, since the native hosting view stays full height.
                .opacity(mini ? 0 : 1)
                .allowsHitTesting(!mini)
                // In mini the window is shorter than the column's minimum; laid out at its
                // expanded size but reporting zero height, it can't push the platter down.
                .frame(height: holdsExpandedLayout && heldHeight > 0 ? heldHeight : nil)
                .frame(height: Self.surfaceHidesInMini && mini ? 0 : nil, alignment: .bottom)
            if player.current != nil {
                // The bottom inset is constant so the platter never shifts vertically.
                NowPlayingBar()
                    .padding(.horizontal, mini ? 0 : inset)
                    .padding(.bottom, platterBottomInset)
                    // Expanded: the platter's drop shadow would spill past the panel; keep it in.
                    // One shape whose parameters animate: switching between two mask views made
                    // SwiftUI crossfade them, drawing the whole platter at partial alpha for the
                    // length of the transition, with rows showing through it.
                    .modifier(PlatterClip(mini: mini))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            #if !NATIVE_FRAME
            if !mini {
                // The window's real edges are out in the shadow margin, so resizing happens here.
                ResizeEdges()
                    .transition(.opacity)
            }
            // The panel's edge line, over everything, following the container as it collapses.
            PanelEdge(cornerRadius: Theme.Radius.window)
                .frame(maxHeight: containerHeight ?? .infinity)
                .opacity(mini ? 0 : 1)
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
            fullHeight = height
            // Held while the native frame animates: following the window frame by frame would
            // relayout the whole column every frame of the expand.
            if !navigation.isMiniPlayer, !navigation.isFrameAnimating { columnHeight = height }
        }
        // Our own window shadow, drawn in the transparent margin around the visible shape.
        .background(alignment: .bottom) {
            #if !NATIVE_FRAME
            if !ArtworkStyle.shared.panel.systemShadow {
                PanelShadow(radius: radius, height: mini ? navigation.platterHeight : containerHeight, bottomInset: mini ? inset : 0)
            }
            #endif
        }
        .onChange(of: ArtworkStyle.shared.panel.systemShadow, initial: true) { _, on in
            AppDelegate.shared?.setSystemShadow(on)
        }
        .padding(Theme.Size.shadowMargin)
        .animation(Theme.Motion.standard, value: player.current?.id)
        .animation(Self.miniAnimation, value: mini)
    }
}

/// The platter's clip: the panel shape, extended upward, while expanded; in mini the window is
/// the platter, so the clip opens out past the shadow margin. Under the native frame the window
/// clips, so there is no mask at all (a mask is an offscreen group, which costs during the move).
private struct PlatterClip: ViewModifier {
    let mini: Bool
    func body(content: Content) -> some View {
        #if NATIVE_FRAME
        content
        #else
        content.mask {
            RoundedRectangle(cornerRadius: mini ? 0 : Theme.Radius.window, style: .continuous)
                .frame(maxHeight: .infinity)
                .padding(.top, -2000)
                .padding(.horizontal, mini ? -Theme.Size.shadowMargin : 0)
                .padding(.bottom, mini ? -Theme.Size.shadowMargin : 0)
        }
        #endif
    }
}

/// The column's clip to the (possibly shrinking) container. The native frame clips with the
/// window instead, and a masked column is an offscreen group that composites above the platter's
/// glass while it animates.
private struct ColumnClip: ViewModifier {
    let containerHeight: CGFloat?
    func body(content: Content) -> some View {
        #if NATIVE_FRAME
        content
        #else
        content.mask(alignment: .bottom) {
            RoundedRectangle(cornerRadius: Theme.Radius.window, style: .continuous)
                .frame(maxHeight: containerHeight ?? .infinity)
        }
        #endif
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
        // The sidebar surface draws its own hairline; a contact shadow on top of it reads as a
        // second edge. Glass has no line of its own, so it keeps the tight shadow.
        let contact = ArtworkStyle.shared.panel.surface == .glass ? 1.0 : 0.0
        // The caster is exactly the panel shape; only its shadow reaches into the margin.
        shape
            .fill(.black)
            .frame(height: height)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, bottomInset)
            // Sized to stay inside the 36pt margin (blur extent + offset), so it never clips.
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.5 : 0.22), radius: 12, y: 5)
            .shadow(color: .black.opacity((colorScheme == .dark ? 0.35 : 0.14) * contact), radius: 1.5, y: 0.5)
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
        // One static control in the top-left corner: the library glyph on the search root, the
        // back chevron on every page. Pages slide beneath it; it only swaps glyphs in place.
        .overlay(alignment: .topLeading) {
            // Alone in the overlay: a second child would make an implicit, centred stack.
            LeadingButton(isBack: !path.isEmpty)
                .padding(.top, Theme.Space.panelInset)
                .padding(.leading, Theme.Space.panelInset)
        }
        .background {
            if !path.isEmpty {
                // ⌘[ goes back; a hidden button carries the shortcut without touching the control.
                Button("Back") { navigation.pop() }
                    .keyboardShortcut("[", modifiers: .command)
                    .hidden()
            }
        }
        .onChange(of: path.last?.id, initial: true) { _, top in
            scrollTracker.activeKey = top ?? ScrollTracker.searchKey
        }
    }
}

private struct LeadingButton: View {
    @Environment(NavigationModel.self) private var navigation
    let isBack: Bool

    private var symbol: String { isBack ? "chevron.left" : "books.vertical" }

    var body: some View {
        Button {
            if isBack { navigation.pop() } else { navigation.open(NavigationModel.library) }
        } label: {
            ZStack {
                // Keyed by symbol so library ↔ back swaps through scale, blur and fade in place.
                Image(systemName: symbol)
                    .font(isBack ? .body.weight(.semibold) : .body)
                    .foregroundStyle(.primary)
                    .id(symbol)
                    .transition(.blurScale)
            }
            .animation(.snappy(duration: 0.22), value: symbol)
            .headerControl()
            // Beside the compact now-playing header, the artwork's colour reaches the edge that
            // faces it: a lit rim on the trailing side and a faint wash just inside it. As the
            // header rises into place the light climbs the edge with it, bottom to top, and is
            // fully drawn once the header is stuck.
            .overlay {
                let style = ArtworkStyle.shared.leadingCast
                let amount = navigation.leadingCastAmount
                InterpolatedColor(navigation.leadingCast) { cast in
                    if let cast {
                        ZStack {
                            // The wash: light from the side falling off across the button, not from
                            // a point. It simply fades in with the header (a wipe cut it in half).
                            Circle().fill(LinearGradient(
                                stops: [.init(color: cast.opacity(style.washOpacity), location: 0), .init(color: .clear, location: style.washReach)],
                                startPoint: .trailing, endPoint: .leading
                            ))
                            .opacity(amount)
                            // The rim climbs the edge, bottom to top, as the header rises.
                            Circle()
                                .strokeBorder(
                                    LinearGradient(stops: [.init(color: .clear, location: style.rimStart), .init(color: cast.opacity(style.rimOpacity), location: 1)], startPoint: .leading, endPoint: .trailing),
                                    lineWidth: style.rimWidth
                                )
                                .mask {
                                    // The soft edge runs past the top at the end of the travel, so
                                    // the rim is complete once the header is in (a feather ending
                                    // exactly at the top left the top fifth missing).
                                    let feather = 0.2
                                    let edge = amount * (1 + feather)
                                    LinearGradient(
                                        stops: [
                                            .init(color: .black, location: 0),
                                            .init(color: .black, location: min(max(edge - feather, 0), 1)),
                                            .init(color: .clear, location: min(max(edge, 0.0001), 1)),
                                        ],
                                        startPoint: .bottom, endPoint: .top
                                    )
                                    .opacity(amount > 0 ? 1 : 0)
                                }
                        }
                        .clipShape(Circle())
                    }
                }
                // Only while a browse page is on top: the library page (or any page without a
                // now-playing header) gets a clean button, even though the amount a page beneath
                // published is kept for when you return to it.
                .opacity(isBack && navigation.path.last?.kind != .library ? 1 : 0)
                .allowsHitTesting(false)
            }
        }
        .buttonStyle(.pressable(scale: 0.88))
        .help(isBack ? "Back" : "Library")
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
            // Discs, notes and marquees stop while a screen sits unseen beneath another; left
            // running, every parked page redrew its spinning artwork thirty times a second.
            .environment(\.screenIsParked, parked)
    }
}

extension EnvironmentValues {
    /// True inside a navigation screen that is mounted but hidden under another.
    @Entry var screenIsParked: Bool = false
}
