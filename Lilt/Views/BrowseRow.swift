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
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                    .fill(.fill.quaternary)
                    .opacity(isHovering ? 0.6 : 0)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(Theme.Motion.quick) { isHovering = hovering }
            // Warm the cache so the page is ready by the time it's clicked.
            if hovering { Task { _ = try? await music.page(for: item) } }
        }
    }

    /// Hovering the artwork offers to play the album, playlist or artist's top songs right here,
    /// without opening the page.
    private var artwork: some View {
        Button {
            Task {
                guard let page = try? await music.page(for: item), !page.tracks.isEmpty else { return }
                player.play(page.tracks, startingAt: 0)
            }
        } label: {
            ArtworkView(url: item.artworkURL, size: Theme.Size.rowArtwork, radius: artworkRadius)
                .playOverlay(isVisible: isHoveringArtwork, radius: artworkRadius, size: Theme.Size.rowArtwork)
        }
        .buttonStyle(.plain)
        .onHover { isHoveringArtwork = $0 }
        .help("Play")
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
