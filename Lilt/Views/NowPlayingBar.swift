import SwiftUI

struct NowPlayingBar: View {
    @Environment(PlayerService.self) private var player
    @Environment(NavigationModel.self) private var navigation
    @Environment(YTMusicClient.self) private var music
    @Environment(NoticeCenter.self) private var notices: NoticeCenter?
    @Environment(ScrollTracker.self) private var scrollTracker
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage(PlatterDoubleClick.key) private var doubleClick = PlatterDoubleClick.miniPlayer

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous) }
    private var platter: PlatterStyle { ArtworkStyle.shared.platter }
    private var playCast: PlayCastStyle { ArtworkStyle.shared.playCast }
    /// The cover's colour as every part of the platter wears it, from the interpolated accent.
    private func coverPalette(_ accent: Color?) -> CoverPalette {
        CoverPalette(accent: accent, colorScheme: colorScheme, surface: .platter, windowStyle: ArtworkStyle.shared.shownWindowStyle(reduceTransparency: reduceTransparency))
    }
    /// The platter's shadow, rim and fill strengths for the window style on screen.
    private var surface: SurfaceStyle.Platter { ArtworkStyle.shared.surface(colorScheme, reduceTransparency: reduceTransparency).platter }

    /// The cover's colour as the play capsule samples it, for the rim and glow. In dark mode it
    /// is drawn as the glass controls' cast is (the palette's accent container: the cover's hue
    /// at a set lightness), so the edge catches clear coloured light rather than white mixed with
    /// a dim colour.
    private var cast: Color? {
        guard platter.castEdge || platter.castGlow, let url = player.displayArtworkURL else { return nil }
        let sampled = ImageCache.shared.tint(for: url, saturationBoost: playCast.saturation)
        guard colorScheme == .dark else { return sampled }
        return coverPalette(nil).casting(sampled).accentContainer
    }

    /// 0 when nothing scrolls beneath the platter, 1 once rows are passing under it. As a mini
    /// player the platter is the whole window, so it always wears its glass.
    private var glassVisibility: CGFloat {
        // Held at full through a mini transition and for a beat after it: the tracker reports
        // nothing mid-move, and a platter going bare with rows passing beneath it reads as a flash.
        platter.alwaysGlass || navigation.isMiniPlayer || navigation.isFrameAnimating || holdsGlass ? 1 : min(max(scrollTracker.activeRemainingBelow / ScrollTracker.glassFadeDistance, 0), 1)
    }

    /// The current artwork, for the ambient fill (any cached size will do once blurred).
    private var ambientImage: NSImage? {
        guard surface.tintOpacity > 0, let url = player.displayArtworkURL else { return nil }
        return ImageCache.shared.cached(url) ?? ImageCache.shared.anyVariant(for: url)
    }

    /// The cover's dominant colour, the seed of the platter's palette.
    private var accent: Color? {
        guard let url = player.displayArtworkURL else { return nil }
        return ImageCache.shared.accent(for: url, saturationBoost: ArtworkStyle.shared.palette.accentSaturation)
    }

    @State private var isHoveringPlatter = false
    @State private var titleWidth: CGFloat = 0
    /// True from a mini change until the transition has settled (see `holdGlass`). Starts true,
    /// so the first frame after launch already wears the glass rather than fading it in once the
    /// scroll tracker reports.
    @State private var holdsGlass = true
    @State private var glassHold: Task<Void, Never>?

    /// Keeps the platter's glass on through a transition and a little past it, so it never drops
    /// out between the move ending and the scroll tracker reporting rows beneath again.
    private func holdGlass() {
        holdsGlass = true
        glassHold?.cancel()
        glassHold = Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.6))
            if !Task.isCancelled { holdsGlass = false }
        }
    }
    /// The platter in the window's coordinate space, to settle hover after the frame animates.
    @State private var platterFrame: CGRect = .zero
    /// How far the grab handle has to be pulled before it counts as a drag rather than a click.
    private static let handlePull: CGFloat = 12
    /// The list stays mounted for a moment after it has closed, so its spring out completes.
    @State private var queueLingers = false
    @State private var lingering: Task<Void, Never>?
    /// The drawer stays mounted for a moment after it has closed, so its spring out completes.
    @State private var ambienceLingers = false
    @State private var ambienceLingering: Task<Void, Never>?

    /// Hover as the pointer actually stands once the window has stopped moving under it.
    private func settleHover() {
        guard let window = AppDelegate.shared?.panelFrame, window.width > 0 else { return }
        let mouse = NSEvent.mouseLocation
        let local = CGPoint(x: mouse.x - window.minX, y: window.maxY - mouse.y)
        let hovering = platterFrame.contains(local)
        if hovering != isHoveringPlatter { withAnimation(Theme.Motion.quick) { isHoveringPlatter = hovering } }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: Theme.Space.sm) {
                playerRows
            }
            // The platter's size without the list, so the mini window can be sized for the
            // list's eventual height instead of chasing the animation.
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { navigation.platterBaseHeight = $0 + Theme.Space.barPadding * 2 }
            // The ambience drawer, under the scrubber, opened with an option-click on the cover.
            // It reveals the way the list does: mounted while it opens or lingers shut, its
            // height and opacity following `ambienceReveal`, so the platter and, in mini, the
            // window ride one curve.
            let ambienceReveal = navigation.ambienceReveal
            if navigation.isAmbienceVisible || ambienceReveal > 0 || ambienceLingers {
                InterpolatedColor(accent) { AmbiencePanel(accent: $0) }
                    .padding(.top, Theme.Space.sm)
                    // Never below nothing, should a curve overshoot on the way shut.
                    .frame(height: max(AmbiencePanel.extent * ambienceReveal, 0), alignment: .top)
                    // Cut off below as it's revealed, as the list is.
                    .clipShape(BleedingRect(dx: Theme.Space.barPadding))
                    .opacity(min(max(ambienceReveal, 0), 1))
                    .allowsHitTesting(ambienceReveal > 0.5)
            }
            // The list is always here, shown as far as `queueReveal` says: pulled out by the
            // grab handle, or sprung to an end. It hangs from under the scrubber, cut off below.
            // Mounted only while it shows (a mounted list, even at no height, takes the
            // platter's double-click for itself), and for a beat after, so its spring out
            // isn't cut short when the model value lands on zero.
            let reveal = navigation.queueReveal
            if navigation.isQueueVisible || reveal > 0 || queueLingers {
                // The list's text takes the cover's colour as the title and artist above do.
                InterpolatedColor(accent) { QueueList(accent: $0) }
                    .padding(.top, Theme.Space.sm)
                    // Never below nothing, should a curve overshoot on the way shut.
                    .frame(height: max(QueueList.extent(manual: player.upcoming.count, automatic: player.automaticUpcoming.count) * reveal, 0), alignment: .top)
                    // Cut off below as it's revealed, but not at the sides: the rows' highlights
                    // and the covers' shadows reach into the platter's padding, and the platter's
                    // own shape bounds them there.
                    .clipShape(BleedingRect(dx: Theme.Space.barPadding))
                    .opacity(min(max(reveal, 0), 1))
                    .allowsHitTesting(reveal > 0.5)
            }
        }
        // The player rows never give up height to the list below them.
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: navigation.isQueueVisible || navigation.queueReveal > 0) { _, showing in
            lingering?.cancel()
            if showing {
                queueLingers = true
            } else {
                lingering = Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    guard !Task.isCancelled else { return }
                    queueLingers = false
                }
            }
        }
        .onChange(of: navigation.isAmbienceVisible || navigation.ambienceReveal > 0) { _, showing in
            ambienceLingering?.cancel()
            if showing {
                ambienceLingers = true
            } else {
                ambienceLingering = Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    guard !Task.isCancelled else { return }
                    ambienceLingers = false
                }
            }
        }
        .padding(Theme.Space.barPadding)
        // The list slides in from under the scrubber; clipping to the platter keeps that, and the
        // list itself, inside the glass while the platter grows and shrinks.
        .clipShape(shape)
        // A sheet-style grab handle at the top, only on hover (the platter stays clean), that
        // shows or hides what's up next. A click toggles. A pull drags the list out with the
        // pointer, and on release it springs to whichever end is nearer, or the way it was flicked.
        .overlay(alignment: .top) {
            Capsule()
                .fill(.secondary.opacity(0.55))
                .frame(width: 30, height: 4)
                .padding(.vertical, 3)
                .padding(.horizontal, Theme.Space.sm)
                .background {
                    // The hit area runs well wider and deeper than the capsule: 120 by 20 points
                    // from the platter's top edge, which stops short of anything else clickable.
                    GrabHandle(
                        onToggle: { AppDelegate.shared?.setQueueVisible(!navigation.isQueueVisible) },
                        onDrag: { travel in AppDelegate.shared?.dragQueue(by: travel) },
                        onRelease: { travel, velocity in AppDelegate.shared?.settleQueue(travel: travel, velocity: velocity) },
                        // Over the handle the platter counts as hovered, whatever SwiftUI's own
                        // tracking says while the pointer is on an AppKit view. Leaving the handle
                        // for the rest of the platter re-enters that tracking; leaving the platter
                        // altogether is its exit to report.
                        onHover: { inside in if inside, !navigation.isFrameAnimating { withAnimation(Theme.Motion.quick) { isHoveringPlatter = true } } },
                        pull: Self.handlePull,
                        toolTip: navigation.isQueueVisible ? "Hide Up Next" : "Show Up Next"
                    )
                    .padding(.horizontal, -37)
                    .padding(.bottom, -10)
                }
                // Shown on hover, but always there to click: gated on the hover state, a click
                // landing as that state dropped for a frame went nowhere.
                .opacity(isHoveringPlatter ? 1 : 0)
        }
        .onChange(of: navigation.isFrameAnimating) { _, animating in
            if !animating { settleHover() }
            holdGlass()
        }
        .onChange(of: navigation.isMiniPlayer) { _, _ in holdGlass() }
        // At launch the scroll tracker hasn't reported yet, so the glass would arrive a beat late.
        .onAppear { holdGlass() }
        // The window needs the platter's height to size itself as a mini player.
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { navigation.platterHeight = $0 }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { platterFrame = $0 }
        .background {
            // Glass, tint, edge and shadow only earn their place when rows pass beneath; at the
            // end of a list the platter is bare.
            let layers = platter.layers(
                tintOpacity: surface.tintOpacity,
                hoverBrightness: surface.hoverBrightness,
                hovering: isHoveringPlatter,
                reduceTransparency: reduceTransparency
            )
            // Neutral for the scheme: what the glass tint and the backing calm the glass with.
            let neutral: Color = colorScheme == .dark ? .black : .white
            ZStack {
                // Backing: a faint fill behind the glass, so busy rows beneath read quieter.
                if layers.backing > 0 {
                    shape.fill(neutral.opacity(layers.backing))
                }
                Color.clear
                    .glassEffect(
                        (layers.material == .clear ? Glass.clear : Glass.regular).tint(layers.glassTint > 0 ? neutral.opacity(layers.glassTint) : nil),
                        in: .rect(cornerRadius: Theme.Radius.panel, style: .continuous)
                    )
                    // In mini the window's own shadow does this job; a soft shadow in the app's
                    // pixels would just grow the window's hit shape and get a hard shadow of its own.
                    .shadow(
                        color: .black.opacity(navigation.isMiniPlayer ? 0 : surface.shadowOpacity),
                        radius: surface.shadowRadius,
                        y: surface.shadowOffsetY
                    )
                // Frost: the regular glass over the clear, at its strength, for a clear platter
                // that would otherwise show too much of what passes beneath.
                if layers.frost > 0 {
                    Color.clear
                        .glassEffect(.regular, in: .rect(cornerRadius: Theme.Radius.panel, style: .continuous))
                        .opacity(layers.frost)
                }
                // The artwork itself, blurred across the platter: vibrant for any cover, where a
                // flat average colour turns rainbow art into mud.
                if let ambientImage {
                    shape.fill(.clear)
                        .overlay {
                            // Keyed by cover so one blurred wash crossfades into the next.
                            Image(nsImage: ambientImage)
                                .resizable()
                                .scaledToFill()
                                .saturation(surface.tintSaturation)
                                .blur(radius: surface.tintBlur)
                                .id(player.displayArtworkURL)
                                .transition(.opacity)
                        }
                        // A touch brighter under the pointer, like glass catching more light.
                        .opacity(layers.coverOpacity)
                        .clipShape(shape)
                }
                // The dominant colour pooled behind the cover (or along the top), as if it spilled.
                InterpolatedColor(accent) { accent in
                    let palette = coverPalette(accent)
                    if let wash = palette.wash, palette.washOpacity > 0 {
                        shape.fill(
                            EllipticalGradient(
                                colors: [wash, .clear],
                                center: platter.accentPlacement.unitPoint,
                                startRadiusFraction: 0,
                                endRadiusFraction: platter.cornerAccentRadius
                            )
                        )
                        .opacity(layers.washOpacity)
                    }
                }
            }
            .opacity(glassVisibility)
            // The blurred fill is laid out larger than the platter; clipping hides that but
            // doesn't stop it stealing clicks from the row above. Decoration never takes hits.
            .allowsHitTesting(false)
        }
        // Glass is composited by the window server, so the app's own pixels here are fully
        // transparent and macOS would pass clicks straight through to the window behind. A
        // near-invisible fill makes the platter solid to hit-testing.
        //
        // Double-click anywhere on the platter collapses to the mini player or expands back (or,
        // as Settings says, opens and closes Up Next). The
        // gesture lives on this fill rather than over the rows: a double-tap wrapped around the
        // content swallows single clicks on the buttons inside it (the cover, the artist), while
        // here it only sees clicks that nothing above has claimed, so the whole rectangle counts
        // except where a control takes the click for itself.
        .background {
            shape.fill(Color.black.opacity(0.012))
                .onTapGesture(count: 2) { doubleClick.perform(on: AppDelegate.shared) }
        }
        .contentShape(shape)
        // Right-click anywhere on the platter: the playing song's own actions.
        .contextMenu {
            if let track = player.current {
                RowMenuItems(
                    groups: RowMenu.nowPlaying(music.withLinks(track), isLiked: player.isLiked),
                    playlists: music.ownPlaylists,
                    addedTo: music.addedTo[track.id] ?? [],
                    perform: { perform($0, on: track) },
                    add: { playlist in RowMenu.add(track, to: playlist, music: music, notices: notices) }
                )
            }
        }
        .onHover { hovering in
            // While the native frame animates, the platter moves under a still pointer and AppKit
            // reports exits and enters that mean nothing; hover is settled once it stops.
            guard !navigation.isFrameAnimating else { return }
            withAnimation(Theme.Motion.quick) { isHoveringPlatter = hovering }
            if hovering, let track = player.current { music.warmOwnPlaylists(videoId: track.id) }
        }
        .warmsLinks(for: player.current, whileHovering: isHoveringPlatter)
        // Border slider scales the rim; 0.10 default reads as a subtle glass edge.
        // The rim as on the play capsule: the cover's colour on the lit top edge, and a soft wash
        // of it inside falling off from the top. Both optional, both interpolated between songs.
        .overlay {
            InterpolatedColor(cast) { cast in
                if let cast, platter.castGlow, playCast.glowOpacity > 0 {
                    shape.fill(
                        LinearGradient(
                            stops: [
                                .init(color: cast.opacity(playCast.glowOpacity), location: 0),
                                .init(color: .clear, location: playCast.glowHeight),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .blur(radius: playCast.glowBlur)
                    .clipShape(shape)
                    .opacity(glassVisibility)
                    .allowsHitTesting(false)
                }
            }
        }
        .overlay {
            InterpolatedColor(cast) { cast in
                Color.clear.glassEdge(
                    shape,
                    opacity: min(surface.borderOpacity * 6, 1) * glassVisibility,
                    cast: platter.castEdge ? cast : nil,
                    castMix: playCast.rimMix,
                    blur: platter.castEdge ? playCast.rimBlur : 0,
                    blend: platter.castEdge ? playCast.rimBlend.blendMode : .normal,
                    bottomScale: platter.bottomEdge(dark: colorScheme == .dark)
                )
            }
            .allowsHitTesting(false)
        }
        .animation(Theme.Motion.quick, value: glassVisibility)
        .animation(Theme.Motion.standard, value: player.displayArtworkURL)
    }


    /// The title's fade, in unit space across its measured width: solid, then fading out to clear
    /// beneath the like button wherever that button shows.
    static func titleMaskStops(width: CGFloat, hovering: Bool, liked: Bool) -> [Gradient.Stop] {
        let w = max(width, 1)
        let shows = hovering || liked
        let clear = shows ? 26.0 : 0
        let fade = shows ? Double(Theme.Space.xl) : 0
        return [
            .init(color: .black, location: 0),
            .init(color: .black, location: max(0, 1 - (clear + fade) / w)),
            .init(color: .clear, location: max(0, 1 - clear / w)),
            .init(color: .clear, location: 1),
        ]
    }

    /// Title row, transport row and scrubber.
    @ViewBuilder
    private var playerRows: some View {
        HStack(spacing: Theme.Space.md) {
            artwork
            // Title and artist take a little of the cover's colour too, the artist half as much.
            InterpolatedColor(accent) { accent in
                let palette = coverPalette(accent)
                VStack(alignment: .leading, spacing: 2) {
                    MarqueeText(
                        text: player.displayTitle,
                        isActive: isHoveringPlatter,
                        font: .callout.weight(.medium),
                        color: palette.style(\.primary, or: .primary)
                    )
                    // The title does nothing with a click, so a double-click on it still reaches
                    // the platter's mini toggle beneath.
                    .allowsHitTesting(false)
                    ArtistLink(name: player.displayArtist, item: player.current?.artistItem, color: palette.secondary ?? .secondary)
                }
                // The text fades out beneath the like button (below) rather than making room, so
                // nothing shifts when the pointer arrives; a liked thumb stays without the pointer,
                // and so does the fade. The fade is a gradient in unit space
                // from the measured width: fixed-width pieces in a stack blanked the whole title
                // whenever the row was momentarily narrow.
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { titleWidth = $0 }
                .mask {
                    LinearGradient(
                        stops: Self.titleMaskStops(width: titleWidth, hovering: isHoveringPlatter, liked: player.isLiked),
                        startPoint: .leading, endPoint: .trailing
                    )
                    .transaction { $0.animation = nil }
                }
                // The mask and the text it masks move as one while the platter changes size;
                // without this the mask's bounds animated apart from the text, clipping the
                // title's leading edge and hiding the artist line for a few frames.
                .geometryGroup()
                // Fills to the row's trailing edge (a trailing spacer took a share of the row),
                // so the like lines up with the repeat button below it.
                .frame(maxWidth: .infinity, alignment: .leading)
                // Like, at the right of the title on hover; the text fades out beneath it (see
                // the mask above). Anchored to the row, outside the geometry group: inside it,
                // the group's frame animation was re-targeted by every window step of the mini
                // transition and the button lurched along the trailing edge.
                .overlay(alignment: .trailing) {
                    // Coloured as shuffle and repeat are: the label colour taking a share of the
                    // cover's, not the raw accent.
                    ModeButton(
                        symbol: player.isLiked ? "hand.thumbsup.fill" : "hand.thumbsup",
                        isOn: player.isLiked,
                        revealed: isHoveringPlatter,
                        tint: palette.control ?? palette.mono,
                        dimTint: palette.dimControl
                    ) {
                        player.toggleLike()
                    }
                    // No transaction of its own: one that silenced the reveal also silenced the
                    // layout animation, so it snapped across the mini transition while shuffle
                    // and repeat eased.
                }
            }
        }

        // The glyphs take a faint share of the cover's colour (less than the scrubber), and
        // it slides to the next song's like everything else.
        InterpolatedColor(accent) { accent in
            #if DEBUG
            let _ = PlatterBuildCounts.notePalette(player)
            let _ = PlatterBuildCounts.notePlayhead(player)
            #endif
            let palette = coverPalette(accent)
            let tint = palette.control ?? palette.mono
            let dim = palette.dimControl
            HStack(spacing: 0) {
                // Shuffle and repeat flank the transport; they appear on hover, or stay when on.
                ModeButton(symbol: "shuffle", isOn: player.isShuffled, revealed: isHoveringPlatter, tint: tint, dimTint: dim) {
                    player.toggleShuffle()
                }
                Spacer(minLength: 0)
                HStack(spacing: Theme.Space.xl) {
                    TransportButton(symbol: "backward.fill", label: "Previous", size: Theme.Size.controlIcon, enabled: player.current != nil) {
                        player.previous()
                    }
                    TransportButton(symbol: player.isPlaying ? "pause.fill" : "play.fill", label: player.isPlaying ? "Pause" : "Play", size: Theme.Size.playIcon, enabled: player.current != nil) {
                        player.togglePlayPause()
                    }
                    TransportButton(symbol: "forward.fill", label: "Next", size: Theme.Size.controlIcon, enabled: player.hasNext) {
                        player.next()
                    }
                }
                .foregroundStyle(tint)
                Spacer(minLength: 0)
                ModeButton(
                    symbol: player.repeatMode == .one ? "repeat.1" : "repeat",
                    isOn: player.repeatMode != .off,
                    revealed: isHoveringPlatter,
                    tint: tint,
                    dimTint: dim
                ) {
                    player.cycleRepeat()
                }
            }
        }

        scrubber
    }

    private func perform(_ action: RowAction, on track: Track) {
        switch action {
        case .startMix: RowMenu.startMix(for: track, player: player, music: music, notices: notices)
        case .like, .unlike: RowMenu.setLiked(action == .like, track, player: player, music: music, notices: notices)
        // The player resolves the playing song's links itself, but a lookup may land first.
        case .goToArtist: RowMenu.open(music.withLinks(track).artistItem, navigation: navigation)
        case .goToAlbum: RowMenu.open(music.withLinks(track).albumItem, navigation: navigation)
        case .copyLink: RowMenu.copyLink(RowMenu.webURL(for: track), named: track.title, notices: notices)
        default: break
        }
    }

    /// Artwork opens the album when we know which one it is.
    @ViewBuilder
    private var artwork: some View {
        let view = ArtworkView(url: player.displayArtworkURL, size: Theme.Size.barArtwork, radius: Theme.Radius.barArtwork, context: .player)
        let album = player.current?.albumItem
        Button {
            // Option-click: the ambience drawer, the platter's one hidden door.
            if NSEvent.modifierFlags.contains(.option) {
                AppDelegate.shared?.setAmbienceVisible(!navigation.isAmbienceVisible)
                return
            }
            // In mini there is no column to show the album in: expand first, then open it.
            if navigation.isMiniPlayer { AppDelegate.shared?.setMiniPlayer(false) }
            if let album { navigation.open(album) }
        } label: { view }
            .buttonStyle(.plain)
            .help(album?.title ?? (navigation.isMiniPlayer ? "Expand" : "Option-click for ambience"))
    }

    /// The palette role the elapsed and total times wear: the tertiary lines', so on Glass they
    /// follow its ladder up off a light backdrop with the rest.
    static let timeRole: KeyPath<CoverPalette, Color?> = \.tertiary

    /// The playhead's line colour: the controls' (or, with the platter's own override, its own
    /// share of the accent). The ambience drawer's levels beneath it wear the same.
    static func lineColor(_ palette: CoverPalette, accent: Color?) -> Color? {
        let platter = ArtworkStyle.shared.platter
        return platter.scrubberLikeControls ? palette.control : accent.map { palette.mono.mix(with: $0, by: platter.scrubberTint) }
    }

    /// Elapsed on the left, the line in the middle, total on the right.
    private var scrubber: some View {
        // The line is coloured like the controls (or, with the platter's own override, its own
        // share of the accent), the times like the tertiary lines, and the colour slides to the
        // next song's rather than switching.
        InterpolatedColor(accent) { accent in
            #if DEBUG
            let _ = PlatterBuildCounts.notePalette(player)
            #endif
            let palette = coverPalette(accent)
            PlatterPlayhead(
                line: Self.lineColor(palette, accent: accent),
                times: palette[keyPath: Self.timeRole]
            )
        }
    }
}

/// The platter's playhead: the elapsed time, the line and the length. It is the only part of the
/// platter that follows the clock, so it reads the clock in a body of its own and a tick rebuilds
/// this alone; out of sight it holds the time it last showed and doesn't follow at all.
private struct PlatterPlayhead: View {
    let line: Color?
    let times: Color?
    @Environment(PlayerService.self) private var player
    @Environment(\.screenIsParked) private var parked
    @State private var isScrubbing = false
    @State private var scrubValue: Double = 0
    /// The time last shown, kept out of SwiftUI's sight: it's only written while the clock is read.
    @State private var shown = Shown()
    private final class Shown { var time: Double = 0 }

    /// The clock, read only while the panel can be seen; out of sight, the time it last showed.
    private var clock: Double {
        guard !parked else { return shown.time }
        #if DEBUG
        PlatterBuildCounts.notePlayhead(player)
        #endif
        shown.time = player.currentTime
        return shown.time
    }

    var body: some View {
        let time = isScrubbing ? scrubValue : clock
        HStack(spacing: Theme.Space.xs + 2) {
            Text(Self.timeString(time))
                .fixedSize()
            Scrubber(
                value: .constant(time),
                range: 0...max(player.duration, 1),
                onEditing: { value, ended in
                    scrubValue = value
                    if ended {
                        player.seek(to: value)
                        isScrubbing = false
                    } else {
                        isScrubbing = true
                    }
                },
                tint: line.map { NSColor($0) }
            )
            .frame(height: 12)
            Text(Self.timeString(player.duration))
                .fixedSize()
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(times.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.tertiary))
    }

    private static func timeString(_ seconds: Double) -> String {
        let total = Int(seconds.rounded(.down))
        let (h, m, s) = (total / 3600, total % 3600 / 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

/// Shuffle / repeat: faint while hovering the platter, solid when on, hidden otherwise.
private struct ModeButton: View {
    /// Tooltip by glyph: the one view serves shuffle, repeat and the mini-player toggle.
    private var help: String {
        if symbol.hasPrefix("repeat") { return "Repeat" }
        if symbol == "shuffle" { return "Shuffle" }
        if symbol.hasPrefix("hand.thumbsup") { return isOn ? "Unlike" : "Like" }
        return ""
    }
    let symbol: String
    let isOn: Bool
    let revealed: Bool
    /// Colour when on; nil for the label colour.
    var tint: Color? = nil
    /// Colour when off (while revealed); nil for the secondary label colour.
    var dimTint: Color? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                // Glyph swap (e.g. collapse ↔ expand arrows): scale, blur and fade in place.
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .id(symbol)
                    .transition(.blurScale)
            }
            .animation(Theme.Motion.symbol, value: symbol)
            .foregroundStyle(isOn ? (tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.primary)) : (dimTint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.secondary)))
            .frame(width: 28, height: 28)
            .contentShape(Circle())
        }
        .buttonStyle(.pressable(scale: 0.88))
        .opacity(isOn ? 1 : revealed ? 0.7 : 0)
        .allowsHitTesting(isOn || revealed)
        .help(help)
    }
}

private struct TransportButton: View {
    let symbol: String
    /// What the button does, as the Controls menu names it: its tooltip and its VoiceOver name,
    /// which would otherwise be the glyph's.
    let label: String
    let size: CGFloat
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                // Keyed by symbol so a change (play ↔ pause) swaps glyphs through the transition.
                Image(systemName: symbol)
                    .font(.system(size: size, weight: .semibold))
                    .id(symbol)
                    .transition(.blurScale)
            }
            .animation(Theme.Motion.symbol, value: symbol)
            .frame(width: 36, height: 36)
            .contentShape(Circle())
        }
        .buttonStyle(.pressable(scale: 0.9))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// A rectangle that reaches `dx` past its frame on the left and right: a clip that cuts only at
/// the top and bottom.
private struct BleedingRect: Shape {
    let dx: CGFloat
    func path(in rect: CGRect) -> Path { Path(rect.insetBy(dx: -dx, dy: 0)) }
}

#if DEBUG
/// How many times the platter has worked out its scrubber's palette from the cover, and built
/// its playhead, by player. Tests read it to check that the clock moving rebuilds the playhead
/// alone, and not at all while nobody can see the panel. Keyed by player, so tests running
/// alongside don't count each other's.
@MainActor
enum PlatterBuildCounts {
    static var palettes: [ObjectIdentifier: Int] = [:]
    static var playheads: [ObjectIdentifier: Int] = [:]

    static func notePalette(_ player: PlayerService) { palettes[ObjectIdentifier(player), default: 0] += 1 }
    static func notePlayhead(_ player: PlayerService) { playheads[ObjectIdentifier(player), default: 0] += 1 }
}
#endif
