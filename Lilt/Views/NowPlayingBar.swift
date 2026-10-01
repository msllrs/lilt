import SwiftUI

struct NowPlayingBar: View {
    @Environment(PlayerService.self) private var player
    @Environment(NavigationModel.self) private var navigation

    @State private var isScrubbing = false
    @State private var scrubValue: Double = 0
    @State private var isHoveringArtist = false

    var body: some View {
        VStack(spacing: Theme.Space.sm) {
            HStack(spacing: Theme.Space.md) {
                artwork
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.displayTitle)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    artistLine
                }
                Spacer(minLength: 0)
            }

            scrubber

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
        }
        .padding(Theme.Space.barPadding)
        .glassEffect(.regular, in: .rect(cornerRadius: Theme.Radius.panel, style: .continuous))
    }

    /// Artwork opens the album when we know which one it is.
    @ViewBuilder
    private var artwork: some View {
        let view = ArtworkView(url: player.displayArtworkURL, size: Theme.Size.barArtwork, radius: Theme.Radius.barArtwork)
        if let album = player.current?.albumItem {
            Button { navigation.open(album) } label: { view }
                .buttonStyle(.plain)
                .help(album.title)
        } else {
            view
        }
    }

    /// Artist name opens the artist page when we know who they are.
    @ViewBuilder
    private var artistLine: some View {
        if let artist = player.current?.artistItem {
            Button { navigation.open(artist) } label: {
                Text(player.displayArtist)
                    .font(.caption)
                    .foregroundStyle(isHoveringArtist ? .primary : .secondary)
                    .underline(isHoveringArtist)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .onHover { isHoveringArtist = $0 }
        } else {
            Text(player.displayArtist)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var scrubber: some View {
        VStack(spacing: Theme.Space.xs) {
            Slider(
                value: Binding(
                    get: { isScrubbing ? scrubValue : player.currentTime },
                    set: { scrubValue = $0 }
                ),
                in: 0...max(player.duration, 1)
            ) { editing in
                if editing {
                    scrubValue = player.currentTime
                    isScrubbing = true
                } else {
                    player.seek(to: scrubValue)
                    isScrubbing = false
                }
            }
            .controlSize(.mini)
            HStack {
                Text(timeString(isScrubbing ? scrubValue : player.currentTime))
                Spacer()
                Text(timeString(player.duration))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.tertiary)
        }
    }

    private func timeString(_ seconds: Double) -> String {
        let total = Int(seconds.rounded(.down))
        let (h, m, s) = (total / 3600, total % 3600 / 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

private struct TransportButton: View {
    let symbol: String
    let size: CGFloat
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .frame(width: 36, height: 36)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
    }
}
