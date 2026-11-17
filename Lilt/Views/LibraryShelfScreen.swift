import SwiftUI

/// One of the library's shelves. Library shows the first few of each and a See All row; the
/// whole shelf is a page of its own, with a field to narrow it.
enum LibraryShelf: String, CaseIterable {
    case playlists, albums, artists

    /// How many rows Library shows of each shelf before See All, which Settings chooses from
    /// `previewCounts`.
    static let previewKey = "libraryPreviewCount"
    static let previewCounts = [8, 16, 32]
    static let standardPreview = 8

    /// The chosen count, or the standard one for anything Settings doesn't offer.
    static func preview(stored: Int) -> Int {
        previewCounts.contains(stored) ? stored : standardPreview
    }

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
    @State private var scroll = ListScroll()
    @State private var isFiltering = false
    @Namespace private var glass

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

    /// Titled as Library is, centred and medium when Library's is. The filter waits behind a
    /// search button in the trailing slot, so the header is Library's height until it's wanted;
    /// on Liquid Glass the button's glass flows out into the field's.
    private var header: some View {
        let centred = ArtworkStyle.shared.centredLibraryTitle
        return GlassEffectContainer {
            HStack(spacing: Theme.Space.sm) {
                // Slot for the back button, which the navigation column draws statically on top.
                Color.clear.frame(width: Theme.Size.headerRow, height: Theme.Size.headerRow)
                if isFiltering {
                    SearchField(text: $filter, prompt: "Filter \(shelf.title)", screenId: shelf.page.id) { focused in
                        if !focused { foldFilterIfEmpty() }
                    }
                    // The field lets an Escape through once it's empty.
                    .onKeyPress(.escape) {
                        foldFilterIfEmpty()
                        return .handled
                    }
                    .glassEffectID(Self.filterGlass, in: glass)
                } else {
                    if centred { Spacer(minLength: 0) }
                    Text(shelf.title)
                        .font(centred ? .body.weight(.medium) : .body)
                    Spacer(minLength: 0)
                    Button(action: openFilter) {
                        Image(systemName: "magnifyingglass")
                            .font(.body)
                            .foregroundStyle(.primary)
                            .headerControl()
                    }
                    .buttonStyle(.plain)
                    .glassEffectID(Self.filterGlass, in: glass)
                    .help("Filter \(shelf.title)")
                }
            }
        }
        .frame(height: Theme.Size.headerRow)
        .background {
            // ⌘F, as Find is anywhere on the Mac.
            Button("Filter \(shelf.title)", action: openFilter)
                .keyboardShortcut("f")
                .opacity(0)
                .accessibilityHidden(true)
        }
        .padding(.top, Theme.Space.panelInset)
        .padding(.horizontal, Theme.Space.panelInset)
        .padding(.bottom, Theme.Space.sm)
        .headerBackdrop(visibility: scroll.backdropVisibility)
    }

    private static let filterGlass = "filter"

    private func openFilter() {
        withAnimation(Theme.Motion.standard) { isFiltering = true }
    }

    /// A filter typed in keeps the field: folding it away would hide why the list is short.
    private func foldFilterIfEmpty() {
        guard filter.isEmpty else { return }
        withAnimation(Theme.Motion.standard) { isFiltering = false }
    }

    private var list: some View {
        // Filtered once a build: each keystroke runs the filter over the whole shelf.
        let shown = shown
        return ScrollView {
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
        .onScrollGeometryChange(for: ListScroll.self) { geometry in
            ListScroll(ScrollMetrics(
                offset: geometry.contentOffset.y + geometry.contentInsets.top,
                contentHeight: geometry.contentSize.height,
                visibleHeight: geometry.containerSize.height - geometry.contentInsets.top - geometry.contentInsets.bottom
            ))
        } action: { _, scroll in
            self.scroll = scroll
            scrollTracker.report(remainingBelow: scroll.remainingBelow, for: shelf.page.id)
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
                Text("See All")
                    .font(.caption)
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
