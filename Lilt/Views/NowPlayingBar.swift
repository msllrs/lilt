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
        navigation.isMiniPlayer ? 1 : min(max(scrollTracker.activeRemainingBelow / 24, 0), 1)
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

    var body: some View {
        VStack(spacing: Theme.Space.sm) {
            VStack(spacing: Theme.Space.sm) {
                playerRows
            }
            // The platter's size without the list, so the mini window can be sized for the
            // list's eventual height instead of chasing the animation.
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { navigation.platterBaseHeight = $0 + Theme.Space.barPadding * 2 }
            if navigation.isQueueVisible {
                QueueList()
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        // The player rows never give up height to the list below them.
        .fixedSize(horizontal: false, vertical: true)
        .padding(Theme.Space.barPadding)
        // The list slides in from under the scrubber; clipping to the platter keeps that, and the
        // list itself, inside the glass while the platter grows and shrinks.
        .clipShape(shape)
        // Double-click anywhere on the platter opens or closes what's up next. The whole
        // rectangle counts, not just the controls and text.
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { AppDelegate.shared?.setQueueVisible(!navigation.isQueueVisible) }
        // Collapse to a mini player, or expand back: tucked in the top-right corner, only on hover.
        .overlay(alignment: .topTrailing) {
            InterpolatedColor(accent) { accent in
                ModeButton(
                    symbol: navigation.isMiniPlayer ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left",
                    isOn: false,
                    revealed: isHoveringPlatter,
                    dimTint: accent.map { Color.secondary.mix(with: $0, by: platter.controlsTint) }
                ) {
                    AppDelegate.shared?.setMiniPlayer(!navigation.isMiniPlayer)
                }
            }
            .padding(Theme.Space.xs)
        }
        .onHover { hovering in
            withAnimation(Theme.Motion.quick) { isHoveringPlatter = hovering }
        }
        // The window needs the platter's height to size itself as a mini player.
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { navigation.platterHeight = $0 }
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
        .background { shape.fill(Color.black.opacity(0.012)) }
        .contentShape(shape)
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
                    ArtistLink(name: player.displayArtist, item: player.current?.artistItem, color: artist ?? .secondary)
                }
            }
            // Room for the mode button in the corner, only while it's showing (hover).
            // Eases in with the button; snaps back when the pointer leaves. Scoped to the hover
            // change alone: blanking the whole transaction froze the title's other motion too,
            // so it jumped while the rest of the platter eased.
            .padding(.trailing, isHoveringPlatter ? Theme.Space.lg : 0)
            .animation(isHoveringPlatter ? Theme.Motion.quick : nil, value: isHoveringPlatter)
            Spacer(minLength: 0)
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
        if album != nil || navigation.isMiniPlayer {
            Button {
                // In mini there is no column to show the album in: expand first, then open it.
                if navigation.isMiniPlayer { AppDelegate.shared?.setMiniPlayer(false) }
                if let album { navigation.open(album) }
            } label: { view }
                .buttonStyle(.plain)
                .help(album?.title ?? "Expand")
        } else {
            view
        }
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
        .help(symbol.hasPrefix("repeat") ? "Repeat" : "Shuffle")
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
