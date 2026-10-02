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
    /// 0 = ordinary row, 1 = the playing track's disc-in-a-pill. Animated explicitly so the
    /// artwork corners, row highlight, spindle hole and rotation all move as one.
    @State private var disc: CGFloat

    init(track: Track, isCurrent: Bool, isPlaying: Bool, action: @escaping () -> Void) {
        self.track = track
        self.isCurrent = isCurrent
        self.isPlaying = isPlaying
        self.action = action
        _disc = State(initialValue: isCurrent ? 1 : 0)
    }

    /// One full turn every eight seconds.
    private static let degreesPerSecond: Double = 45

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
            TimelineView(.animation(minimumInterval: 1 / 30, paused: !isSpinning)) { context in
                let elapsed = resumedAt.map { context.date.timeIntervalSince($0) } ?? 0
                let angle = baseAngle + (isSpinning ? elapsed * Self.degreesPerSecond : 0)
                ArtworkView(url: track.artworkURL, size: Theme.Size.rowArtwork, radius: artworkRadius, rotation: .degrees(angle))
                    .overlay { spindleHole.opacity(disc).scaleEffect(disc) }
            }
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
        .onChange(of: isSpinning) { _, spinning in
            if spinning {
                resumedAt = .now
            } else if let resumedAt {
                baseAngle = (baseAngle + Date.now.timeIntervalSince(resumedAt) * Self.degreesPerSecond)
                    .truncatingRemainder(dividingBy: 360)
                self.resumedAt = nil
            }
        }
        .onChange(of: isCurrent) { _, current in
            // No longer the playing track: settle back upright by the shorter way round.
            guard !current else { return }
            resumedAt = nil
            withAnimation(Theme.Motion.standard) {
                baseAngle = baseAngle > 180 ? 360 : 0
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
