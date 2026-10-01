import SwiftUI

/// An artist name that opens the artist page wherever it appears. Falls back to plain text when
/// we don't know the artist's id. Pushes onto the shared navigation model, so it works inside the
/// stack and in the now-playing bar alike.
struct ArtistLink: View {
    let name: String
    let item: BrowseItem?
    var font: Font = .caption
    var color: Color = .secondary

    @Environment(NavigationModel.self) private var navigation
    @State private var isHovering = false

    var body: some View {
        if let item {
            Button {
                navigation.open(item)
            } label: {
                Text(name)
                    .font(font)
                    .foregroundStyle(isHovering ? AnyShapeStyle(.primary) : AnyShapeStyle(color))
                    .underline(isHovering)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
            .help(name)
        } else {
            Text(name)
                .font(font)
                .foregroundStyle(color)
                .lineLimit(1)
        }
    }
}
