import SwiftUI

struct TrackRow: View {
    let track: Track
    let isCurrent: Bool
    let isPlaying: Bool
    let action: () -> Void

    @Environment(PlayerService.self) private var player
    @State private var isHovering = false
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
    /// Row highlight: the usual concentric radius at rest, a full pill while playing.
    private var rowRadius: CGFloat { lerp(Theme.Radius.row, (Theme.Size.rowArtwork + (Theme.Space.xs + 2) * 2) / 2, disc) }

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
            .padding(.horizontal, Theme.Space.sm)
            .padding(.vertical, Theme.Space.xs + 2)
            .contentShape(RoundedRectangle(cornerRadius: rowRadius, style: .continuous))
            .background {
                RoundedRectangle(cornerRadius: rowRadius, style: .continuous)
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

    @ViewBuilder
    private var trailing: some View {
        if let duration = track.durationText {
            Text(duration)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
    }
}
