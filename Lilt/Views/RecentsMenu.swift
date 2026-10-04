import SwiftUI

/// A clock button beside the search field that drops down recently played tracks and recently
/// opened pages.
struct RecentsMenu: View {
    @Environment(RecentsStore.self) private var recents
    @Environment(PlayerService.self) private var player
    @Environment(NavigationModel.self) private var navigation

    var body: some View {
        Menu {
            if !recents.played.isEmpty {
                Section("Recently played") {
                    ForEach(recents.played) { track in
                        Button {
                            player.play([track], startingAt: 0)
                        } label: {
                            label(title: track.title, subtitle: track.artist, artwork: track.artworkURL, fallback: "music.note")
                        }
                    }
                }
            }
            if !recents.viewed.isEmpty {
                Section("Recently viewed") {
                    ForEach(recents.viewed) { item in
                        Button {
                            navigation.open(item)
                        } label: {
                            label(
                                title: item.title,
                                subtitle: item.subtitle,
                                artwork: item.artworkURL,
                                fallback: item.kind == .artist ? "person.crop.circle" : "square.stack"
                            )
                        }
                    }
                }
            }
            if recents.isEmpty {
                Text("Nothing yet")
            } else {
                Divider()
                Button("Clear Recents", role: .destructive) { recents.clear() }
            }
        } label: {
            Image(systemName: "clock")
                .font(.body)
                .foregroundStyle(.secondary)
                .headerControl()
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Recents")
        // Recents survive relaunches but thumbnails only come from the in-memory cache; warm it
        // (from the disk cache, mostly) so the menu has artwork the first time it opens.
        .task(id: recents.played.count + recents.viewed.count) {
            ImageCache.shared.prefetch(recents.played.map(\.artworkURL) + recents.viewed.map(\.artworkURL))
        }
    }

    /// Menus render the label's image as the item icon, so use cached artwork when we have it.
    @ViewBuilder
    private func label(title: String, subtitle: String, artwork: URL?, fallback: String) -> some View {
        let text = subtitle.isEmpty ? title : "\(title) — \(subtitle)"
        if let artwork, let thumb = ImageCache.shared.thumbnail(for: artwork) {
            Label { Text(text) } icon: { Image(nsImage: thumb) }
        } else {
            Label(text, systemImage: fallback)
        }
    }
}
