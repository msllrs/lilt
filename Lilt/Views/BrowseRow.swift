import SwiftUI

/// A tappable artist, album or playlist.
struct BrowseRow: View {
    let item: BrowseItem

    @State private var isHovering = false

    var body: some View {
        NavigationLink(value: item) {
            HStack(spacing: Theme.Space.md) {
                ArtworkView(
                    url: item.artworkURL,
                    size: Theme.Size.rowArtwork,
                    radius: item.kind == .artist ? Theme.Size.rowArtwork / 2 : Theme.Radius.rowArtwork
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.body)
                        .lineLimit(1)
                    subtitle
                }
                Spacer(minLength: Theme.Space.sm)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
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
        }
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
            Text(item.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}
