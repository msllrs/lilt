import SwiftUI

/// Your YouTube Music home feed, shown when the search field is empty.
struct HomeScreen: View {
    @Environment(YTMusicClient.self) private var music
    @Environment(ScrollTracker.self) private var scrollTracker
    @Environment(NavigationModel.self) private var navigation
    @Environment(NoticeCenter.self) private var notices: NoticeCenter?

    private enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    @State private var phase: Phase = .loading
    @State private var sections: [HomeSection] = []
    /// The search screen's, whose header backdrop Home's scroll fades in.
    @Binding var scroll: ListScroll

    init(scroll: Binding<ListScroll>) {
        _scroll = scroll
        // Render cached shelves immediately; the task refreshes if the cache is stale.
        if let cached = MainActor.assumeIsolated({ AppDelegate.shared?.music.cachedHome }) {
            _sections = State(initialValue: cached)
            _phase = State(initialValue: .loaded)
        }
    }

    var body: some View {
        // A feed that lands quickly comes straight in; only a slow one shows the skeleton first.
        DelayedPlaceholder(isLoading: phase == .loading) {
            switch phase {
            case .loading:
                EmptyView()
            case .failed(let message):
                EmptyHint(symbol: "exclamationmark.triangle", title: "Couldn't load Home", detail: message) {
                    phase = .loading
                    Task { await load() }
                }
            case .loaded where sections.isEmpty:
                EmptyHint(symbol: "magnifyingglass", title: "Search YouTube Music", detail: "Songs, artists, albums and playlists.")
            case .loaded:
                feed
            }
        } placeholder: {
            ScrollView { Skeleton.Rows(count: 7, header: true) }
                .scrollDisabled(true)
        }
        .task { await load() }
        // ⌘R, while the feed is the screen on top (no page opened over it).
        .onChange(of: navigation.refreshRequest) { _, _ in
            if navigation.path.isEmpty { Task { await load(refresh: true) } }
        }
    }

    private var feed: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                    CollapsibleSection(title: section.title, scope: "home", items: section.items) { item in
                        switch item {
                        case .track(let track):
                            TrackRows(tracks: section.tracks, only: track)
                        case .browse(let browse):
                            BrowseRow(item: browse)
                        }
                    }
                    // Shelf by shelf, as the root comes back under a staggering transition.
                    .entrance(.row(index))
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
            scrollTracker.report(remainingBelow: scroll.remainingBelow, for: ScrollTracker.searchKey)
        }
    }

    /// A `refresh` (⌘R) fetches even a fresh feed, eases a change in, and keeps the shelves on
    /// screen if it fails.
    private func load(refresh: Bool = false) async {
        do {
            let fresh = try await music.home(forceRefresh: refresh)
            if refresh { notices?.postRefresh(RefreshOutcome(old: sections, new: fresh), of: "Home") }
            withAnimation(refresh ? Theme.Motion.standard : nil) {
                sections = fresh
                phase = .loaded
            }
        } catch is CancellationError {
        } catch {
            Diagnostics.shared.record(.screen, "Home couldn't load: \(error)")
            if !(refresh && phase == .loaded) { phase = .failed(error.localizedDescription) }
            if refresh { notices?.postRefresh(.failed, of: "Home") }
        }
    }
}
