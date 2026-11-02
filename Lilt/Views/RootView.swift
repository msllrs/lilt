import SwiftUI

struct RootView: View {
    @Environment(PlayerService.self) private var player
    @Environment(NavigationModel.self) private var navigation
    @Environment(NoticeCenter.self) private var notices
    /// The column's height while expanded. In mini the window is only as tall as the platter, so
    /// the (invisible) column keeps this size instead of reflowing, and reports none of it.
    @State private var columnHeight: CGFloat = 0
    /// Settings ▸ Appearance, and the system's Reduce Motion: read once here for every disc.
    @AppStorage(SpinningArtwork.spinsKey) private var spinsPlayingCover = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let mini = navigation.isMiniPlayer
        let inset = Theme.Space.panelInset
        // The window itself is the container: its frame animates between the column and the
        // platter (see AppDelegate), and our surfaces and clips just fill it. The column is held
        // at its expanded layout only while the frame animates or in mini, when the hosting view
        // is pinned at the expanded height; a column that has never been laid out expanded
        // (launched in mini) holds the height the window is heading for. While expanded and idle
        // it just fills the view: a fixed height fed back from the view's own measurement runs a
        // frame behind a live resize, overflows, and an overflowing stack is centred, cutting
        // the header and the platter.
        let holdsExpandedLayout = mini || navigation.isFrameAnimating
        let heldHeight = columnHeight > 0 ? columnHeight : navigation.expandedFrameHeight
        ZStack(alignment: .bottom) {
            // The panel's surface, always mounted. It never fades or resizes: it stays at the
            // expanded height, bottom-anchored like the column, and the window's own frame
            // reveals or hides it. Sized by SwiftUI it would lag the window by a layout pass,
            // leaving rows hanging above its top edge for a frame; in mini the platter sits on it
            // as when expanded. It hangs from an overlay so its extra height never enters the
            // stack's layout: an oversized stack gets centred, which would push the platter
            // below the window.
            Color.clear
                .overlay(alignment: .bottom) {
                    PanelBackground()
                        .frame(height: heldHeight <= 0 ? nil : heldHeight)
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
                // The window clips and reveals the column; no mask of our own (a masked or fading
                // column animating beneath the platter renders as an offscreen group that lands
                // above the platter's glass, so rows showed through it mid-move). It fades with
                // the move: in mini it would otherwise still be there behind the platter's glass,
                // since the hosting view stays full height.
                .opacity(mini ? 0 : 1)
                .allowsHitTesting(!mini)
                // In mini the window is shorter than the column's minimum; laid out at its
                // expanded size but reporting zero height, it can't push the platter down.
                .frame(height: holdsExpandedLayout && heldHeight > 0 ? heldHeight : nil)
            if player.current != nil {
                // Expanded, the platter keeps its inset; in mini the window is the platter.
                NowPlayingBar()
                    .padding(.horizontal, mini ? 0 : inset)
                    .padding(.bottom, mini ? 0 : inset)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            // Notices float just above the platter, centred, clear of its controls and of the
            // header; with nothing playing, at the foot of the column. Not in mini: the window is
            // the platter, so a notice could only cover it (or grow the window for a few seconds).
            if !mini {
                NoticeHost()
                    .padding(.horizontal, inset)
                    .padding(.bottom, inset + (player.current != nil ? navigation.platterHeight + Theme.Space.sm : 0))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
            // Held while the frame animates: following the window frame by frame would relayout
            // the whole column every frame of the expand.
            if !navigation.isMiniPlayer, !navigation.isFrameAnimating { columnHeight = height }
        }
        .animation(Theme.Motion.standard, value: player.current?.id)
        .animation(Theme.Motion.frame, value: mini)
        // A notice is about what you just did in the panel; once it's hidden or folded to the
        // platter, it's done with.
        .onChange(of: mini) { _, _ in notices.dismiss() }
        .onChange(of: navigation.isPanelHidden) { _, hidden in if hidden { notices.dismiss() } }
        // Everything outside a screen (the platter's marquee and disc) pauses while nobody can
        // see the panel too; screens combine this with their own parked state above.
        .environment(\.screenIsParked, navigation.isPanelOutOfSight)
        .environment(\.discsHoldStill, !spinsPlayingCover || reduceMotion)
    }
}

/// A stack of screens with a subtle horizontal hand-off. NavigationStack swaps views instantly
/// on macOS; here the search root stays alive underneath and pages ease in from the right by a
/// few points, fading, and back out the same way.
private struct NavigationColumn: View {
    @Environment(NavigationModel.self) private var navigation
    @Environment(ScrollTracker.self) private var scrollTracker
    @Environment(AuthService.self) private var auth

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
        // In mini the column is still mounted behind the platter, only faded out, so its discs
        // and notes would turn on unseen.
        let outOfSight = navigation.isPanelOutOfSight || navigation.isMiniPlayer
        ZStack {
            SearchScreen()
                .parked(path.isEmpty ? nil : .leading, travel: Self.travel, blur: Self.blur, animation: Self.exit, value: path, outOfSight: outOfSight)
            ForEach(Array(path.enumerated()), id: \.element.id) { index, item in
                let isTop = index == path.count - 1
                Group {
                    if item.kind == .library {
                        LibraryScreen()
                    } else {
                        BrowseScreen(item: item)
                    }
                }
                .parked(isTop ? nil : .leading, travel: Self.travel, blur: Self.blur, animation: Self.exit, value: path, outOfSight: outOfSight)
                .transition(.offset(x: Self.travel).combined(with: .opacity).animation(Self.enter))
            }
        }
        .animation(Self.enter, value: path)
        // One static control in the top-left corner: the library glyph on the search root, the
        // back chevron on every page. Pages slide beneath it; it only swaps glyphs in place.
        .overlay(alignment: .topLeading) {
            // Alone in the overlay: a second child would make an implicit, centred stack. Signed
            // out there is no library to open, so no button.
            if auth.isSignedIn {
                LeadingButton(isBack: !path.isEmpty)
                    .padding(.top, Theme.Space.panelInset)
                    .padding(.leading, Theme.Space.panelInset)
            }
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
    @Environment(YTMusicClient.self) private var music
    @Environment(\.colorScheme) private var colorScheme
    let isBack: Bool

    private var symbol: String { isBack ? "chevron.left" : "books.vertical" }

    /// On an album the chevron is one of the page's controls, so it takes the page's tint (the
    /// same mix and contrast guard as its Play and shuffle glyphs); the library glyph stays plain.
    private func glyphStyle(_ accent: Color?) -> AnyShapeStyle {
        BrowseScreen.coverTint(kind: .album, accent: accent, colorScheme: colorScheme).style(\.control, or: .primary)
    }

    var body: some View {
        Button {
            if isBack { navigation.pop() } else { navigation.open(NavigationModel.library) }
        } label: {
            // Slides between albums' colours, and to and from plain, as pages come and go.
            InterpolatedColor(isBack ? navigation.leadingTintAccent : nil) { accent in
                ZStack {
                    // Keyed by symbol so library ↔ back swaps through scale, blur and fade in place.
                    Image(systemName: symbol)
                        .font(isBack ? .body.weight(.semibold) : .body)
                        .foregroundStyle(glyphStyle(accent))
                        .id(symbol)
                        .transition(.blurScale)
                }
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
                InterpolatedColor(navigation.leadingCast) { sampled in
                    if let sampled {
                        // Dark glass has no tonal range for a dim colour to sit on, so there the
                        // cast is lifted towards white and added as light rather than laid over.
                        let dark = colorScheme == .dark
                        let cast = style.drawn(sampled, dark: dark)
                        let washOpacity = style.washOpacity(dark: dark)
                        ZStack {
                            // The wash: light from the side falling off across the button, not from
                            // a point. It simply fades in with the header (a wipe cut it in half).
                            Circle().fill(LinearGradient(
                                stops: [.init(color: cast.opacity(washOpacity), location: 0), .init(color: .clear, location: style.washReach)],
                                startPoint: .trailing, endPoint: .leading
                            ))
                            .opacity(amount)
                            // The rim climbs the edge, bottom to top, as the header rises. On the
                            // glass highlight's own path, centred on the outline, so it colours
                            // that highlight rather than lining the inside of it.
                            Circle().inset(by: -0.5)
                                .stroke(
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
                                    // The stroke straddles the outline; a mask the size of the
                                    // frame would cut away its outer half.
                                    .padding(-1)
                                }
                        }
                        .blendMode(style.blend(dark: dark))
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
        // Hovering the library button fetches the library, and with it every cover, so the
        // screen and its scroll are ready by the click.
        .onHover { hovering in
            if hovering, !isBack { Task { _ = try? await music.library() } }
        }
        .help(isBack ? "Back" : "Library")
    }
}

private extension View {
    /// Keeps a screen mounted but slid aside and inert while another one is on top.
    @ViewBuilder
    func parked<V: Equatable>(_ edge: HorizontalEdge?, travel: CGFloat, blur: CGFloat, animation: Animation, value: V, outOfSight: Bool) -> some View {
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
            .environment(\.screenIsParked, parked || outOfSight)
    }
}

extension EnvironmentValues {
    /// True inside a navigation screen that is mounted but hidden under another, and throughout
    /// the panel while nobody can see it.
    @Entry var screenIsParked: Bool = false
    /// The playing song's disc stays a disc but doesn't turn: spinning is off in Settings ▸
    /// Appearance, or Reduce Motion is on.
    @Entry var discsHoldStill: Bool = false
}
