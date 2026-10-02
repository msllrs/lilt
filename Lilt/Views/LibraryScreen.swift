import SwiftUI

/// Your YouTube Music library: playlists, saved albums and followed artists.
struct LibraryScreen: View {
    @Environment(YTMusicClient.self) private var music
    @Environment(ScrollTracker.self) private var scrollTracker

    private enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    @State private var phase: Phase = .loading
    @State private var content = LibraryContent()
    @State private var scrollOffset: CGFloat = 0

    var body: some View {
        body_
            .safeAreaBar(edge: .top, spacing: 0) { header }
            .task { await load() }
    }

    private var header: some View {
        HStack(spacing: Theme.Space.sm) {
            // Slot for the back button, which the navigation column draws statically on top.
            Color.clear.frame(width: 28, height: 28)
            Text("Library")
                .font(.callout.weight(.medium))
            Spacer()
        }
        .padding(.top, Theme.Space.panelInset)
        .padding(.horizontal, Theme.Space.panelInset)
        .padding(.bottom, Theme.Space.sm)
        .headerBackdrop(visibility: Self.backdropVisibility(forScrollOffset: scrollOffset))
    }

    @ViewBuilder
    private var body_: some View {
        switch phase {
        case .loading:
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            EmptyHint(symbol: "exclamationmark.triangle", title: "Couldn't load your library", detail: message)
        case .loaded where content.isEmpty:
            EmptyHint(symbol: "books.vertical", title: "Nothing saved yet", detail: "Albums, playlists and artists you save on YouTube Music appear here.")
        case .loaded:
            list
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                section("Playlists", content.playlists)
                section("Albums", content.albums)
                section("Artists", content.artists)
            }
            .padding(.horizontal, Theme.Space.rowInset)
            .padding(.bottom, Theme.Space.sm)
        }
        .scrollIndicators(.never)
        .scrollEdgeEffectStyle(.soft, for: .all)
        .onScrollGeometryChange(for: ScrollMetrics.self) { geometry in
            ScrollMetrics(
                offset: geometry.contentOffset.y + geometry.contentInsets.top,
                contentHeight: geometry.contentSize.height,
                visibleHeight: geometry.containerSize.height - geometry.contentInsets.top - geometry.contentInsets.bottom
            )
        } action: { _, metrics in
            scrollOffset = metrics.offset
            scrollTracker.report(remainingBelow: metrics.remainingBelow, for: NavigationModel.library.id)
        }
    }

    /// Empty sections still show, with YouTube's own explanation, so it's clear the page loaded
    /// and the account simply has nothing saved there.
    @ViewBuilder
    private func section(_ title: String, _ items: [BrowseItem]) -> some View {
        SectionHeader(title)
        if items.isEmpty {
            Text(title == "Albums" ? "Albums you save to your library will show here."
                : title == "Artists" ? "Artists will show here when you save their music."
                : "Playlists you create or save will show here.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, Theme.Space.sm)
                .padding(.vertical, Theme.Space.xs)
        } else {
            ForEach(items) { BrowseRow(item: $0) }
        }
    }

    private func load() async {
        do {
            content = try await music.library()
            phase = .loaded
        } catch is CancellationError {
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}
