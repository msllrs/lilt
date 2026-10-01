import SwiftUI

struct TrackRow: View {
    let track: Track
    let isCurrent: Bool
    let isPlaying: Bool
    let action: () -> Void

    @State private var isHovering = false
    @State private var isHoveringArtist = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.md) {
                ArtworkView(url: track.artworkURL, size: Theme.Size.rowArtwork, radius: Theme.Radius.rowArtwork)
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.body)
                        .lineLimit(1)
                    artistLine
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

    /// The artist name opens the artist page when we know who they are.
    @ViewBuilder
    private var artistLine: some View {
        if let artist = track.artistItem {
            NavigationLink(value: artist) {
                Text(track.artist)
                    .font(.caption)
                    .foregroundStyle(isHoveringArtist ? .primary : .secondary)
                    .underline(isHoveringArtist)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .onHover { isHoveringArtist = $0 }
        } else {
            Text(track.artist)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
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
