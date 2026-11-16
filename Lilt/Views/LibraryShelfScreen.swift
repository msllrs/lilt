import SwiftUI

/// One of the library's shelves. Library shows the first few of each and a See All row; the
/// whole shelf is a page of its own, with a field to narrow it.
enum LibraryShelf: String, CaseIterable {
    case playlists, albums, artists

    /// How many rows Library shows before See All.
    static let preview = 6

    var title: String {
        switch self {
        case .playlists: "Playlists"
        case .albums: "Albums"
        case .artists: "Artists"
        }
    }

    /// The shelf's page, as the navigation stack holds it.
    var page: BrowseItem { BrowseItem(id: "library/\(rawValue)", kind: .library, title: title, subtitle: "", artworkURL: nil) }

    init?(page: BrowseItem) {
        guard page.kind == .library, page.id.hasPrefix("library/"), let shelf = LibraryShelf(rawValue: String(page.id.dropFirst(8))) else { return nil }
        self = shelf
    }

    func items(in content: LibraryContent) -> [BrowseItem] {
        switch self {
        case .playlists: content.playlists
        case .albums: content.albums
        case .artists: content.artists
        }
    }

    /// The items whose title or byline holds `filter`, ignoring case and accents.
    static func filtered(_ items: [BrowseItem], by filter: String) -> [BrowseItem] {
        let filter = filter.trimmingCharacters(in: .whitespaces)
        guard !filter.isEmpty else { return items }
        return items.filter { $0.title.localizedStandardContains(filter) || $0.subtitle.localizedStandardContains(filter) }
    }
}

/// A library shelf in full: every playlist, album or artist, narrowed by the field at the top.
struct LibraryShelfScreen: View {
    let shelf: LibraryShelf

    @Environment(YTMusicClient.self) private var music
    @Environment(ScrollTracker.self) private var scrollTracker
    @State private var content: LibraryContent
    @State private var filter = ""
    @State private var scrollOffset: CGFloat = 0

    init(shelf: LibraryShelf, music: YTMusicClient? = nil) {
        self.shelf = shelf
        let music = music ?? MainActor.assumeIsolated { AppDelegate.shared?.music }
        _content = State(initialValue: MainActor.assumeIsolated { music?.cachedLibrary } ?? LibraryContent())
    }

    private var shown: [BrowseItem] { LibraryShelf.filtered(shelf.items(in: content), by: filter) }

    var body: some View {
        list
            .safeAreaBar(edge: .top, spacing: 0) { header }
            .task { if let fresh = try? await music.library() { content = fresh } }
    }

    private var header: some View {
        VStack(spacing: Theme.Space.sm) {
            HStack(spacing: Theme.Space.sm) {
                // Slot for the back button, which the navigation column draws statically on top.
                Color.clear.frame(width: Theme.Size.headerRow, height: Theme.Size.headerRow)
                Text(shelf.title)
                    .font(.body)
                Spacer(minLength: 0)
            }
            .frame(height: Theme.Size.headerRow)
            SearchField(text: $filter, prompt: "Filter \(shelf.title)", screenId: shelf.page.id)
        }
        .padding(.top, Theme.Space.panelInset)
        .padding(.horizontal, Theme.Space.panelInset)
        .padding(.bottom, Theme.Space.sm)
        .headerBackdrop(visibility: Self.backdropVisibility(forScrollOffset: scrollOffset))
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(shown) { BrowseRow(item: $0) }
                if shown.isEmpty {
                    Text(filter.isEmpty ? "Nothing here yet." : "No \(shelf.title.lowercased()) match “\(filter)”.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, Theme.Space.rowPadding)
                        .padding(.vertical, Theme.Space.xs)
                }
            }
            .padding(.horizontal, Theme.Space.rowInset)
            .padding(.bottom, Theme.Space.sm)
        }
        .scrollIndicators(.never)
        .panelScrollEdge()
        .onScrollGeometryChange(for: ScrollMetrics.self) { geometry in
            ScrollMetrics(
                offset: geometry.contentOffset.y + geometry.contentInsets.top,
                contentHeight: geometry.contentSize.height,
                visibleHeight: geometry.containerSize.height - geometry.contentInsets.top - geometry.contentInsets.bottom
            )
        } action: { _, metrics in
            scrollOffset = metrics.offset
            scrollTracker.report(remainingBelow: metrics.remainingBelow, for: shelf.page.id)
        }
    }
}

/// Library's last row under a shelf's preview: how many there are, and the way to all of them.
struct SeeAllRow: View {
    let shelf: LibraryShelf
    let count: Int

    @Environment(NavigationModel.self) private var navigation
    @State private var isHovering = false

    private static let highlight = RoundedRectangle(cornerRadius: Theme.Radius.rowArtwork + Theme.Space.rowPadding, style: .continuous)

    var body: some View {
        Button {
            navigation.open(shelf.page)
        } label: {
            HStack(spacing: Theme.Space.md) {
                Text("See All \(count)")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, Theme.Space.sm)
            }
            .padding(Theme.Space.rowPadding)
            .contentShape(Self.highlight)
            .background {
                Self.highlight
                    .fill(.fill.quaternary)
                    .opacity(isHovering ? 0.6 : 0)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel("See all \(count) \(shelf.title.lowercased())")
    }
}
