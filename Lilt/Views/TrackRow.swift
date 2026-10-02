import SwiftUI

struct TrackRow: View {
    let track: Track
    let isCurrent: Bool
    let isPlaying: Bool
    let action: () -> Void

    @Environment(PlayerService.self) private var player
    @State private var isHovering = false
    /// The add-to-queue button shows a tick for a moment after a click.
    @State private var showsTick = false
    @State private var justQueued: Task<Void, Never>?
    /// 0 = ordinary row, 1 = the playing track's pill highlight. Animated explicitly, on the
    /// same curve as the artwork's own disc transition.
    @State private var disc: CGFloat

    init(track: Track, isCurrent: Bool, isPlaying: Bool, action: @escaping () -> Void) {
        self.track = track
        self.isCurrent = isCurrent
        self.isPlaying = isPlaying
        self.action = action
        _disc = State(initialValue: isCurrent ? 1 : 0)
    }

    private var isSpinning: Bool { isCurrent && isPlaying }
    private var artworkRadius: CGFloat { lerp(Theme.Radius.rowArtwork, Theme.Size.rowArtwork / 2, disc) }

    private static let horizontalPadding = Theme.Space.sm
    private static let verticalPadding = Theme.Space.xs + 2
    private static let rowHeight = Theme.Size.rowArtwork + verticalPadding * 2

    /// Row highlight corners are concentric with the artwork: its radius plus the padding
    /// between them. The artwork side rounds to a full pill while the disc is showing; the far
    /// side keeps the resting radius.
    private var leadingRadius: CGFloat { min(artworkRadius + Self.horizontalPadding, Self.rowHeight / 2) }
    private var trailingRadius: CGFloat { Theme.Radius.rowArtwork + Self.horizontalPadding }

    private var rowShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: leadingRadius,
            bottomLeadingRadius: leadingRadius,
            bottomTrailingRadius: trailingRadius,
            topTrailingRadius: trailingRadius,
            style: .continuous
        )
    }

    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.md) {
                artwork
                VStack(alignment: .leading, spacing: 2) {
                    MarqueeText(text: track.title, isActive: isHovering, font: .body)
                    ArtistLink(name: track.artist, item: track.artistItem)
                }
                // Takes every point the trailing item doesn't need, so titles run wide when
                // there's no duration to show.
                .frame(maxWidth: .infinity, alignment: .leading)
                trailing
                    .padding(.leading, Theme.Space.sm)
            }
            .padding(.horizontal, Self.horizontalPadding)
            .padding(.vertical, Self.verticalPadding)
            .contentShape(rowShape)
            .background {
                rowShape
                    .fill(.fill.quaternary)
                    .opacity(isCurrent ? 1 : isHovering ? 0.6 : 0)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(Theme.Motion.quick) { isHovering = hovering }
        }
        .onChange(of: isCurrent) { _, current in
            withAnimation(Theme.Motion.standard) { disc = current ? 1 : 0 }
        }
    }

    /// Artwork shows play on row hover; for the current track it toggles pause instead. The
    /// current track's artwork becomes a spinning disc with notes drifting out of it.
    private var artwork: some View {
        Button {
            if isCurrent { player.togglePlayPause() } else { action() }
        } label: {
            SpinningArtwork(
                url: track.artworkURL,
                size: Theme.Size.rowArtwork,
                restRadius: Theme.Radius.rowArtwork,
                isDisc: isCurrent,
                isSpinning: isSpinning
            )
            .playOverlay(
                isVisible: isHovering,
                symbol: isSpinning ? "pause.fill" : "play.fill",
                radius: artworkRadius,
                size: Theme.Size.rowArtwork
            )
            .overlay {
                if isCurrent {
                    NoteEmitterView(isPlaying: isPlaying, center: CGPoint(x: 60, y: 60), artworkURL: track.artworkURL)
                        .frame(width: 120, height: 120)
                        .allowsHitTesting(false)
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// The duration, which on hover gives way to the add-to-queue button in the same spot (a
    /// tick for a moment after a click). The playing track can be queued again too.
    private var trailing: some View {
        ZStack {
            if let duration = track.durationText {
                Text(duration)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .opacity(isHovering ? 0 : 1)
            }
            Button {
                player.enqueue(track)
                AppDelegate.shared?.queueDidChange()
                // A tick to confirm, then back to the queue glyph so it can be added again.
                justQueued?.cancel()
                justQueued = Task {
                    try? await Task.sleep(for: .seconds(1.2))
                    guard !Task.isCancelled else { return }
                    showsTick = false
                }
                showsTick = true
            } label: {
                let symbol = showsTick ? "checkmark" : "text.line.last.and.arrowtriangle.forward"
                ZStack {
                    // Glyph swap: scale, blur and fade in place, like the platter's buttons.
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .id(symbol)
                        .transition(.blurScale)
                }
                .animation(.snappy(duration: 0.22), value: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .contentShape(Circle())
            }
            .buttonStyle(.pressable(scale: 0.85))
            .opacity(isHovering ? 1 : 0)
            .allowsHitTesting(isHovering)
            .help("Add to queue")
        }
    }
}
