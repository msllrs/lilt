import SwiftUI

/// An artist name that opens the artist page wherever it appears. Falls back to plain text when
/// we don't know the artist's id. Pushes onto the shared navigation model, so it works inside the
/// stack and in the now-playing bar alike. Without a colour of its own it takes an album page's
/// palette, or the secondary label colour.
struct ArtistLink: View {
    let name: String
    let item: BrowseItem?
    var font: Font = .caption
    var color: Color? = nil

    @Environment(NavigationModel.self) private var navigation
    @Environment(YTMusicClient.self) private var music
    @Environment(\.coverPalette) private var coverPalette
    @State private var isHovering = false
    @State private var warmer: HoverWarmer?

    private var resting: Color { color ?? coverPalette?.secondary ?? .secondary }
    /// Hover lifts it to the title's colour: the tinted one on an album page.
    private var hovered: AnyShapeStyle { coverPalette.style(\.primary, or: .primary) }

    var body: some View {
        if let item {
            Button {
                navigation.open(item)
            } label: {
                Text(name)
                    .font(font)
                    .foregroundStyle(isHovering ? hovered : AnyShapeStyle(resting))
                    .underline(isHovering)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isHovering = hovering
                // Warms the artist page once the pointer rests here, for the artist shown now:
                // the bar's link stays put while its song, and so its artist, changes.
                if hovering {
                    warmer = HoverWarmer { [music] in
                        if music.cachedPage(for: item) == nil { Task { _ = try? await music.page(for: item) } }
                    }
                }
                warmer?.hovering(hovering)
            }
            .help(name)
        } else {
            Text(name)
                .font(font)
                .foregroundStyle(resting)
                .lineLimit(1)
        }
    }
}
