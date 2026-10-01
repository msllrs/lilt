import SwiftUI

struct TrackRow: View {
    let track: Track
    let isCurrent: Bool
    let isPlaying: Bool
    let action: () -> Void

    @Environment(PlayerService.self) private var player
    @State private var isHovering = false

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

    /// Artwork shows play on row hover; for the current track it toggles pause instead.
    private var artwork: some View {
        Button {
            if isCurrent { player.togglePlayPause() } else { action() }
        } label: {
            ArtworkView(url: track.artworkURL, size: Theme.Size.rowArtwork, radius: Theme.Radius.rowArtwork)
                .playOverlay(
                    isVisible: isHovering,
                    symbol: isCurrent && isPlaying ? "pause.fill" : "play.fill",
                    radius: Theme.Radius.rowArtwork,
                    size: Theme.Size.rowArtwork
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var trailing: some View {
        if isCurrent {
            Image(systemName: isPlaying ? "waveform" : "pause.fill")
                .font(.caption)
                .foregroundStyle(.tint)
                .symbolEffect(.variableColor.iterative, isActive: isPlaying)
                .frame(width: 20)
        } else if let duration = track.durationText {
            Text(duration)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
    }
}
