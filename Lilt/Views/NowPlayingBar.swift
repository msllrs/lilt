import SwiftUI

struct NowPlayingBar: View {
    @Environment(PlayerService.self) private var player
    @Environment(NavigationModel.self) private var navigation
    @Environment(ScrollTracker.self) private var scrollTracker
    @Environment(\.colorScheme) private var colorScheme

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous) }
    private var platter: PlatterStyle { ArtworkStyle.shared.platter }
    private var playCast: PlayCastStyle { ArtworkStyle.shared.playCast }

    /// The cover's colour as the play capsule samples it, for the rim and glow.
    private var cast: Color? {
        guard platter.castEdge || platter.castGlow, let url = player.displayArtworkURL else { return nil }
        return ImageCache.shared.tint(for: url, saturationBoost: playCast.saturation)
    }

    /// 0 when nothing scrolls beneath the platter, 1 once rows are passing under it. As a mini
    /// player the platter is the whole window, so it always wears its glass.
    private var glassVisibility: CGFloat {
        // Held at full through a mini transition and for a beat after it: the tracker reports
        // nothing mid-move, and a platter going bare with rows passing beneath it reads as a flash.
        platter.alwaysGlass || navigation.isMiniPlayer || navigation.isFrameAnimating || holdsGlass ? 1 : min(max(scrollTracker.activeRemainingBelow / 24, 0), 1)
    }

    /// The current artwork, for the ambient fill (any cached size will do once blurred).
    private var ambientImage: NSImage? {
        guard platter.tintOpacity > 0, let url = player.displayArtworkURL else { return nil }
        return ImageCache.shared.cached(url) ?? ImageCache.shared.anyVariant(for: url)
    }

    /// The cover's dominant colour, for the corner accent and the scrubber.
    private var accent: Color? {
        guard let url = player.displayArtworkURL else { return nil }
        return ImageCache.shared.accent(for: url, saturationBoost: platter.scrubberSaturation)
    }

    @State private var isScrubbing = false
    @State private var scrubValue: Double = 0
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
            if navigation.isAmbienceVisible {
                InterpolatedColor(accent) { AmbiencePanel(accent: $0) }
                    .padding(.top, Theme.Space.sm)
                    .transition(.opacity.combined(with: .move(edge: .top)))
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
                    .frame(height: QueueList.extent(manual: player.upcoming.count, automatic: player.automaticUpcoming.count) * reveal, alignment: .top)
                    .clipped()
                    .opacity(reveal)
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
            ZStack {
                Color.clear
                    .glassEffect(.regular, in: .rect(cornerRadius: Theme.Radius.panel, style: .continuous))
                    // In mini the window's own shadow does this job; a soft shadow in the app's
                    // pixels would just grow the window's hit shape and get a hard shadow of its own.
                    .shadow(
                        color: .black.opacity(navigation.isMiniPlayer ? 0 : platter.shadowOpacity),
                        radius: platter.shadowRadius,
                        y: platter.shadowOffsetY
                    )
                // The artwork itself, blurred across the platter: vibrant for any cover, where a
                // flat average colour turns rainbow art into mud.
                if let ambientImage {
                    shape.fill(.clear)
                        .overlay {
                            // Keyed by cover so one blurred wash crossfades into the next.
                            Image(nsImage: ambientImage)
                                .resizable()
                                .scaledToFill()
                                .saturation(platter.tintSaturation)
                                .blur(radius: platter.tintBlur)
                                .id(player.displayArtworkURL)
                                .transition(.opacity)
                        }
                        // A touch brighter under the pointer, like glass catching more light.
                        .opacity(platter.tintOpacity * (isHoveringPlatter ? 1 + platter.hoverBrightness : 1))
                        .clipShape(shape)
                }
                // The dominant colour pooled behind the cover (or along the top), as if it spilled.
                InterpolatedColor(accent) { accent in
                    if let accent, platter.cornerAccentOpacity > 0 {
                        shape.fill(
                            EllipticalGradient(
                                colors: [accent.opacity(platter.cornerAccentOpacity), .clear],
                                center: platter.accentPlacement.unitPoint,
                                startRadiusFraction: 0,
                                endRadiusFraction: platter.cornerAccentRadius
                            )
                        )
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
        // Double-click anywhere on the platter collapses to the mini player or expands back. The
        // gesture lives on this fill rather than over the rows: a double-tap wrapped around the
        // content swallows single clicks on the buttons inside it (the cover, the artist), while
        // here it only sees clicks that nothing above has claimed, so the whole rectangle counts
        // except where a control takes the click for itself.
        .background {
            shape.fill(Color.black.opacity(0.012))
                .onTapGesture(count: 2) { AppDelegate.shared?.setMiniPlayer(!navigation.isMiniPlayer) }
        }
        .contentShape(shape)
        .onHover { hovering in
            // While the native frame animates, the platter moves under a still pointer and AppKit
            // reports exits and enters that mean nothing; hover is settled once it stops.
            guard !navigation.isFrameAnimating else { return }
            withAnimation(Theme.Motion.quick) { isHoveringPlatter = hovering }
        }
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
                    opacity: min(platter.borderOpacity * 6, 1) * glassVisibility,
                    cast: platter.castEdge ? cast : nil,
                    castMix: playCast.rimMix,
                    blur: platter.castEdge ? playCast.rimBlur : 0,
                    blend: platter.castEdge ? playCast.rimBlend.blendMode : .normal
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
                let mono = colorScheme == .dark ? Color.white : Color.black
                let title = accent.map { mono.mix(with: $0, by: platter.textTint) }
                let artist = accent.map { Color.secondary.mix(with: $0, by: platter.textTint * 0.5) }
                VStack(alignment: .leading, spacing: 2) {
                    MarqueeText(
                        text: player.displayTitle,
                        isActive: isHoveringPlatter,
                        font: .callout.weight(.medium),
                        color: title.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.primary)
                    )
                    // The title does nothing with a click, so a double-click on it still reaches
                    // the platter's mini toggle beneath.
                    .allowsHitTesting(false)
                    ArtistLink(name: player.displayArtist, item: player.current?.artistItem, color: artist ?? .secondary)
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
                        tint: accent.map { mono.mix(with: $0, by: platter.controlsTint) } ?? mono,
                        dimTint: accent.map { Color.secondary.mix(with: $0, by: platter.controlsTint) }
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
            let mono = colorScheme == .dark ? Color.white : Color.black
            let tint = accent.map { mono.mix(with: $0, by: platter.controlsTint) } ?? mono
            let dim = accent.map { Color.secondary.mix(with: $0, by: platter.controlsTint) }
            HStack(spacing: 0) {
                // Shuffle and repeat flank the transport; they appear on hover, or stay when on.
                ModeButton(symbol: "shuffle", isOn: player.isShuffled, revealed: isHoveringPlatter, tint: tint, dimTint: dim) {
                    player.toggleShuffle()
                }
                Spacer(minLength: 0)
                HStack(spacing: Theme.Space.xl) {
                    TransportButton(symbol: "backward.fill", size: Theme.Size.controlIcon, enabled: player.current != nil) {
                        player.previous()
                    }
                    TransportButton(symbol: player.isPlaying ? "pause.fill" : "play.fill", size: Theme.Size.playIcon, enabled: player.current != nil) {
                        player.togglePlayPause()
                    }
                    TransportButton(symbol: "forward.fill", size: Theme.Size.controlIcon, enabled: player.hasNext) {
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

    /// Artwork opens the album when we know which one it is.
    @ViewBuilder
    private var artwork: some View {
        let view = ArtworkView(url: player.displayArtworkURL, size: Theme.Size.barArtwork, radius: Theme.Radius.barArtwork, context: .player)
        let album = player.current?.albumItem
        Button {
            // Option-click: the ambience drawer, the platter's one hidden door.
            if NSEvent.modifierFlags.contains(.option) {
                withAnimation(.spring(Theme.Motion.queueSpring)) { AppDelegate.shared?.setAmbienceVisible(!navigation.isAmbienceVisible) }
                return
            }
            // In mini there is no column to show the album in: expand first, then open it.
            if navigation.isMiniPlayer { AppDelegate.shared?.setMiniPlayer(false) }
            if let album { navigation.open(album) }
        } label: { view }
            .buttonStyle(.plain)
            .help(album?.title ?? (navigation.isMiniPlayer ? "Expand" : "Option-click for ambience"))
    }

    /// Elapsed on the left, the line in the middle, total on the right.
    private var scrubber: some View {
        // The line takes on the cover's dominant colour by the tweakable amount, the times a
        // fainter share (like the artist line), and the colour slides to the next song's rather
        // than switching.
        InterpolatedColor(accent) { accent in
            let mono = colorScheme == .dark ? Color.white : Color.black
            let line = accent.map { mono.mix(with: $0, by: platter.scrubberLikeControls ? platter.controlsTint : platter.scrubberTint) }
            let times = accent.map { Color(nsColor: .tertiaryLabelColor).mix(with: $0, by: platter.textTint * 0.5) }
            HStack(spacing: Theme.Space.xs + 2) {
                Text(timeString(isScrubbing ? scrubValue : player.currentTime))
                    .fixedSize()
                Scrubber(
                    value: .constant(isScrubbing ? scrubValue : player.currentTime),
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
                Text(timeString(player.duration))
                    .fixedSize()
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(times.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.tertiary))
        }
    }

    private func timeString(_ seconds: Double) -> String {
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
            .animation(.snappy(duration: 0.22), value: symbol)
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
            .animation(.snappy(duration: 0.22), value: symbol)
            .frame(width: 36, height: 36)
            .contentShape(Circle())
        }
        .buttonStyle(.pressable(scale: 0.9))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
    }
}
