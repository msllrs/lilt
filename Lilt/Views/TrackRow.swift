import SwiftUI

struct TrackRow: View {
    let track: Track
    let isCurrent: Bool
    let isPlaying: Bool
    let action: () -> Void

    @Environment(PlayerService.self) private var player
    @State private var isHovering = false
    /// Disc rotation bookkeeping: the angle it held when playback last paused, and when it
    /// resumed, so the spin continues from where it stopped.
    @State private var baseAngle: Double = 0
    @State private var resumedAt: Date?

    /// One full turn every eight seconds.
    private static let degreesPerSecond: Double = 45

    private var isSpinning: Bool { isCurrent && isPlaying }
    private var artworkRadius: CGFloat { isCurrent ? Theme.Size.rowArtwork / 2 : Theme.Radius.rowArtwork }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.md) {
                artwork
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.body)
                        .lineLimit(1)
                    ArtistLink(name: track.artist, item: track.artistItem)
                }
                Spacer(minLength: Theme.Space.sm)
                trailing
            }
            .padding(.horizontal, Theme.Space.sm)
            .padding(.vertical, Theme.Space.xs + 2)
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                    .fill(.fill.quaternary)
                    .opacity(isCurrent ? 1 : isHovering ? 0.6 : 0)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(Theme.Motion.quick) { isHovering = hovering }
        }
    }

    /// Artwork shows play on row hover; for the current track it toggles pause instead. The
    /// current track's artwork becomes a spinning disc with notes drifting out of it.
    private var artwork: some View {
        Button {
            if isCurrent { player.togglePlayPause() } else { action() }
        } label: {
            TimelineView(.animation(minimumInterval: 1 / 30, paused: !isSpinning)) { context in
                let elapsed = resumedAt.map { context.date.timeIntervalSince($0) } ?? 0
                let angle = baseAngle + (isSpinning ? elapsed * Self.degreesPerSecond : 0)
                ArtworkView(url: track.artworkURL, size: Theme.Size.rowArtwork, radius: artworkRadius, rotation: .degrees(angle))
                    .overlay { if isCurrent { spindleHole } }
            }
            .playOverlay(
                isVisible: isHovering,
                symbol: isSpinning ? "pause.fill" : "play.fill",
                radius: artworkRadius,
                size: Theme.Size.rowArtwork
            )
            .overlay {
                if isCurrent {
                    NoteEmitterView(isPlaying: isPlaying, center: CGPoint(x: 60, y: 60))
                        .frame(width: 120, height: 120)
                        .allowsHitTesting(false)
                }
            }
        }
        .buttonStyle(.plain)
        .animation(Theme.Motion.standard, value: isCurrent)
        .onChange(of: isSpinning) { _, spinning in
            if spinning {
                resumedAt = .now
            } else if let resumedAt {
                baseAngle = (baseAngle + Date.now.timeIntervalSince(resumedAt) * Self.degreesPerSecond)
                    .truncatingRemainder(dividingBy: 360)
                self.resumedAt = nil
            }
        }
    }

    /// The hole in the middle of the record.
    private var spindleHole: some View {
        Circle()
            .fill(.black.opacity(0.75))
            .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 0.5))
            .frame(width: 7, height: 7)
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
