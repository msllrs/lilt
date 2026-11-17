import SwiftUI

struct RootView: View {
    @Environment(PlayerService.self) private var player
    @Environment(NavigationModel.self) private var navigation
    @Environment(NoticeCenter.self) private var notices
    @Environment(PanelRest.self) private var rest
    /// Settings ▸ Appearance ▸ Fade when not in use, and the surface's step for it.
    @AppStorage(PanelRest.enabledKey) private var fadesWhenNotInUse = PanelRest.enabledByDefault
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    /// The column's height while expanded. In mini the window is only as tall as the platter, so
    /// the (invisible) column keeps this size instead of reflowing, and reports none of it.
    @State private var columnHeight: CGFloat = 0
    /// Settings ▸ Appearance, and the system's Reduce Motion: read once here for every disc.
    @AppStorage(SpinningArtwork.spinsKey) private var spinsPlayingCover = true
    @AppStorage(TrackRow.alwaysShowsLengthsKey) private var alwaysShowsLengths = false
    @AppStorage(TrackRow.showsExplicitBadgesKey) private var showsExplicitBadges = true
    @AppStorage(TrackRows.hidesUnavailableKey) private var hidesUnavailableSongs = false
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
        // At rest the column recedes a step as one layer; the platter, Up Next and notices
        // sit outside it and keep their strength.
        let resting = rest.isResting && !mini
        let restingOpacity = ArtworkStyle.shared.surface(colorScheme, reduceTransparency: reduceTransparency).atRest.contentOpacity
        // Rests only where there's a column to recede and someone could see it.
        let canRest = fadesWhenNotInUse && !mini && !navigation.isPanelOutOfSight
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
                .opacity(mini ? 0 : resting ? restingOpacity : 1)
                // Recedes slowly, comes back quickly.
                .animation(resting ? Theme.Motion.rest : Theme.Motion.wake, value: resting)
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
        .onChange(of: canRest, initial: true) { _, can in rest.setAvailable(can) }
        .onChange(of: navigation.isPanelHidden) { _, hidden in if hidden { notices.dismiss() } }
        // Everything outside a screen (the platter's marquee and disc) pauses while nobody can
        // see the panel too; screens combine this with their own parked state above.
        .environment(\.screenIsParked, navigation.isPanelOutOfSight)
        .environment(\.discsHoldStill, !spinsPlayingCover || reduceMotion || Theme.Motion.reducesMotion)
        .environment(\.alwaysShowsLengths, alwaysShowsLengths)
        .environment(\.showsExplicitBadges, showsExplicitBadges)
        .environment(\.hidesUnavailableSongs, hidesUnavailableSongs)
    }
}

/// A stack of screens with a subtle horizontal hand-off. NavigationStack swaps views instantly
/// on macOS; here the search root stays alive underneath and pages ease in from the right by a
/// few points, fading, and back out the same way.
private struct NavigationColumn: View {
    @Environment(NavigationModel.self) private var navigation
    @Environment(ScrollTracker.self) private var scrollTracker
    @Environment(AuthService.self) private var auth

    /// How far a screen travels while entering or leaving; under Reduce Motion, nowhere.
    private static var travel: CGFloat { Theme.Motion.pageTravel }
    /// Softness at the far end of the hand-off. Off: blurring a full column of artwork every
    /// frame is what made the hand-off stutter. Slide and fade are cheap; this isn't.
    private static let blur: CGFloat = 0
    /// The outgoing screen gets out of the way faster than the incoming one arrives, so the two
    /// never read as a double exposure on the glass.
    private static var exit: Animation { Theme.Motion.pageExit }
    private static var enter: Animation { Theme.Motion.pageEnter }

    /// The page transition lab's pick (tweak panel ▸ Page transition); always Current in
    /// release builds.
    @State private var transitions = PageTransitionSettings.shared
    /// The column's size, for whether a hero morph's row is on screen. Changes only as the
    /// panel resizes.
    @State private var width: CGFloat = 320
    @State private var height: CGFloat = 600
    @State private var flights = HeroFlight.shared

    var body: some View {
        let path = navigation.path
        // In mini the column is still mounted behind the platter, only faded out, so its discs
        // and notes would turn on unseen.
        let outOfSight = navigation.isPanelOutOfSight || navigation.isMiniPlayer
        // Switching variants rebuilds the screens (a debug-only change of structure); the
        // current hand-off keeps its own code, untouched.
        Group {
            if transitions.transition == .current {
                currentStack(path, outOfSight: outOfSight)
            } else {
                stagedStack(path, outOfSight: outOfSight, choreography: transitions.choreography)
            }
        }
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

    @ViewBuilder
    private func screen(for item: BrowseItem) -> some View {
        if let shelf = LibraryShelf(page: item) {
            LibraryShelfScreen(shelf: shelf)
        } else if item.kind == .library {
            LibraryScreen()
        } else {
            BrowseScreen(item: item)
        }
    }

    /// The column's hand-off as it ships: the page beneath parks aside on `pageExit` while the
    /// new one slides in on `pageEnter`.
    private func currentStack(_ path: [BrowseItem], outOfSight: Bool) -> some View {
        ZStack {
            SearchScreen()
                .parked(path.isEmpty ? nil : .leading, travel: Self.travel, blur: Self.blur, animation: Self.exit, value: path, outOfSight: outOfSight)
            ForEach(Array(path.enumerated()), id: \.element.id) { index, item in
                let isTop = index == path.count - 1
                Group {
                    screen(for: item)
                }
                .parked(isTop ? nil : .leading, travel: Self.travel, blur: Self.blur, animation: Self.exit, value: path, outOfSight: outOfSight)
                .transition(.offset(x: Self.travel).combined(with: .opacity).animation(Self.enter))
            }
        }
        .animation(Self.enter, value: path)
    }

    /// The screen that last came in on top, pushed or come back to, brings its parts in one by
    /// one if the variant does. Read from each screen's own stamp, so a page's entrance doesn't
    /// change as another is pushed over it.
    private func entrance(for key: String, choreography: PageChoreography) -> PageEntrance? {
        guard let plan = choreography.entrance, let at = navigation.arrivals[key] else { return nil }
        return PageEntrance(plan: plan, startedAt: at)
    }

    /// Any other variant: the screens staged by the choreography (see StagedStack), with the
    /// hero morph's ghost over them.
    private func stagedStack(_ path: [BrowseItem], outOfSight: Bool, choreography: PageChoreography) -> some View {
        let tracksHeroes = choreography.flight != nil
        return StagedStack(path: path, choreography: choreography, outOfSight: outOfSight) { key in
            entrance(for: key, choreography: choreography)
        } root: {
            SearchScreen()
        } page: { item in
            screen(for: item)
        }
        .environment(\.heroTracking, tracksHeroes)
        // The hero morph's ghost, above every page and beneath the header's back button.
        .overlay {
            if tracksHeroes, let flight = flights.flight, let phase = choreography.flight {
                HeroGhost(flight: flight, phase: phase)
                    .id(flight.id)
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { height = $0.height; width = $0.width }
        .onChange(of: path) { old, new in
            if tracksHeroes {
                // On screen: below the header, within the column (under the platter is fine,
                // the ghost flies beneath it like the pages).
                let top = Theme.Space.panelInset + Theme.Size.headerRow + Theme.Space.sm
                flights.pathChanged(from: old, to: new, bounds: CGRect(x: 0, y: top, width: width, height: max(height - top, 0)))
            } else {
                flights.cancel()
            }
        }
    }
}

struct LeadingButton: View {
    @Environment(NavigationModel.self) private var navigation
    @Environment(YTMusicClient.self) private var music
    @Environment(\.colorScheme) private var colorScheme
    let isBack: Bool

    private var symbol: String { isBack ? "chevron.left" : "books.vertical" }

    /// On an album the chevron is one of the page's controls, so it takes the page's palette
    /// (the same control colour and contrast guard as its Play and shuffle glyphs); the library
    /// glyph stays plain.
    private func glyphStyle(_ accent: Color?) -> AnyShapeStyle {
        BrowseScreen.palette(kind: .album, accent: accent, colorScheme: colorScheme).style(\.control, or: .primary)
    }

    var body: some View {
        #if DEBUG
        let _ = PageBuildCounts.leadingButtons += 1
        #endif
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
            .animation(Theme.Motion.symbol, value: symbol)
            .headerControl()
            // Beside the compact now-playing header, the artwork's colour reaches the edge that
            // faces it: a lit rim on the trailing side and a faint wash just inside it. As the
            // header rises into place the light climbs the edge with it, bottom to top, and is
            // fully drawn once the header is stuck.
            .overlay {
                let amount = navigation.leadingCastAmount
                InterpolatedColor(navigation.leadingCast) { sampled in
                    // The cast is the palette's accent container: on dark glass, which has no
                    // tonal range for a dim colour to sit on, lifted towards white and added as
                    // light rather than laid over.
                    GlassCast(
                        shape: Circle(),
                        palette: CoverPalette(accent: nil, cast: sampled, colorScheme: colorScheme, surface: .page),
                        litEdge: .trailing,
                        reveal: amount
                    )
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
    /// Settings ▸ Appearance ▸ Always show song lengths: rows keep their lengths with the
    /// pointer away from the panel.
    @Entry var alwaysShowsLengths: Bool = false
    /// Settings ▸ Appearance ▸ Show explicit badges: an E before the artist of a song YouTube
    /// Music marks explicit.
    @Entry var showsExplicitBadges: Bool = true
    /// Settings ▸ Appearance ▸ Hide unavailable songs: lists leave out the songs YouTube Music
    /// greys out, rather than showing them dimmed.
    @Entry var hidesUnavailableSongs: Bool = false
}
