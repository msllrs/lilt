import SwiftUI

/// A tappable artist, album or playlist.
struct BrowseRow: View {
    let item: BrowseItem

    @Environment(NavigationModel.self) private var navigation
    @Environment(YTMusicClient.self) private var music
    @Environment(PlayerService.self) private var player
    @State private var isHovering = false
    @State private var isHoveringArtwork = false

    private var artworkRadius: CGFloat { item.kind == .artist ? Theme.Size.rowArtwork / 2 : Theme.Radius.rowArtwork }

    var body: some View {
        Button {
            navigation.open(item)
        } label: {
            HStack(spacing: Theme.Space.md) {
                artwork
                VStack(alignment: .leading, spacing: 2) {
                    MarqueeText(text: item.title, isActive: isHovering, font: .body)
                    subtitle
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, Theme.Space.sm)
            }
            .padding(.horizontal, Theme.Space.sm)
            .padding(.vertical, Theme.Space.xs + 2)
            // Concentric with the artwork: its radius plus the padding between them.
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.rowArtwork + Theme.Space.sm, style: .continuous))
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.rowArtwork + Theme.Space.sm, style: .continuous)
                    .fill(.fill.quaternary)
                    .opacity(isHovering ? 0.6 : 0)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
            // Warm the cache so the page is ready by the time it's clicked.
            if hovering { Task { _ = try? await music.page(for: item) } }
        }
    }

    /// Hovering the artwork offers to play the album, playlist or artist's top songs right here,
    /// without opening the page.
    /// The queue was started from this album or playlist (not merely a track it contains).
    private var isPlayingHere: Bool { player.current != nil && player.sourceId == item.id }

    private var artwork: some View {
        let playingHere = isPlayingHere
        let isDisc = playingHere && item.kind != .artist
        return Button {
            if playingHere {
                player.togglePlayPause()
            } else {
                Task {
                    guard let page = try? await music.page(for: item), !page.tracks.isEmpty else { return }
                    player.play(page.tracks, startingAt: 0, source: item)
                }
            }
        } label: {
            // The album or playlist that's playing wears the same spinning record, and the same
            // notes, as the playing track's row.
            SpinningArtwork(
                url: item.artworkURL,
                size: Theme.Size.rowArtwork,
                restRadius: artworkRadius,
                isDisc: isDisc,
                isSpinning: isDisc && player.isPlaying
            )
            .playOverlay(
                isVisible: isHoveringArtwork,
                symbol: playingHere && player.isPlaying ? "pause.fill" : "play.fill",
                radius: isDisc ? Theme.Size.rowArtwork / 2 : artworkRadius,
                size: Theme.Size.rowArtwork
            )
            .overlay {
                if isDisc {
                    NoteEmitterView(isPlaying: player.isPlaying, center: CGPoint(x: 60, y: 60), artworkURL: item.artworkURL)
                        .frame(width: 120, height: 120)
                        .allowsHitTesting(false)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { isHoveringArtwork = $0 }
        .help(playingHere ? (player.isPlaying ? "Pause" : "Play") : "Play")
    }

    /// "Album • Artist • 2019" with the artist tappable, when we know who they are.
    @ViewBuilder
    private var subtitle: some View {
        if let artist = item.artist, let artistItem = item.artistItem, let range = item.subtitle.range(of: artist) {
            HStack(spacing: 0) {
                Text(item.subtitle[..<range.lowerBound])
                ArtistLink(name: artist, item: artistItem)
                Text(item.subtitle[range.upperBound...])
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        } else {
            MarqueeText(text: item.subtitle, isActive: isHovering, font: .caption, color: AnyShapeStyle(.secondary))
        }
    }
}
