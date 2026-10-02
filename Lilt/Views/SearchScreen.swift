import SwiftUI

struct SearchScreen: View {
    @Environment(AuthService.self) private var auth
    @Environment(YTMusicClient.self) private var music
    @Environment(NavigationModel.self) private var navigation
    @Environment(ScrollTracker.self) private var scrollTracker

    private enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    @State private var phase: Phase = .idle
    @State private var results = SearchResults()
    @State private var scrollOffset: CGFloat = 0

    var body: some View {
        @Bindable var navigation = navigation
        content
            // A safe-area *bar* (not inset): results scroll beneath it and the system draws its
            // progressive scroll-edge blur under the field.
            .safeAreaBar(edge: .top, spacing: 0) {
                HStack(spacing: Theme.Space.xs) {
                    Button {
                        navigation.open(NavigationModel.library)
                    } label: {
                        Image(systemName: "books.vertical")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.pressable(scale: 0.88))
                    .help("Library")
                    SearchField(text: $navigation.query)
                    RecentsMenu()
                }
                .padding(.top, Theme.Space.panelInset)
                .padding(.horizontal, Theme.Space.panelInset)
                .padding(.bottom, Theme.Space.sm)
                .headerBackdrop(visibility: Self.backdropVisibility(forScrollOffset: scrollOffset))
            }
            .task(id: navigation.query) { await search() }
    }

    @ViewBuilder
    private var content: some View {
        if !auth.isSignedIn {
            SignedOutView()
        } else {
            switch phase {
            case .idle:
                HomeScreen(scrollOffset: $scrollOffset)
            case .loading:
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                EmptyHint(symbol: "exclamationmark.triangle", title: "Something went wrong", detail: message)
            case .loaded where results.isEmpty:
                EmptyHint(symbol: "music.note", title: "Nothing found", detail: "Try a different search.")
                    .onAppear { scrollTracker.report(remainingBelow: 0, for: ScrollTracker.searchKey) }
            case .loaded:
                resultsList
            }
        }
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let top = results.top {
                    SectionHeader("Top result")
                    BrowseRow(item: top)
                }
                if !results.songs.isEmpty {
                    SectionHeader("Songs")
                    TrackRows(tracks: results.songs)
                }
                browseSection("Artists", results.artists)
                browseSection("Albums", results.albums)
                browseSection("Playlists", results.playlists)
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
            scrollTracker.report(remainingBelow: metrics.contentHeight - metrics.visibleHeight - metrics.offset, for: ScrollTracker.searchKey)
        }
    }

    @ViewBuilder
    private func browseSection(_ title: String, _ items: [BrowseItem]) -> some View {
        if !items.isEmpty {
            SectionHeader(title)
            ForEach(items) { BrowseRow(item: $0) }
        }
    }

    private func search() async {
        let trimmed = navigation.query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { phase = .idle; return }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        if phase == .idle { phase = .loading }
        do {
            let found = try await music.search(trimmed)
            guard !Task.isCancelled else { return }
            results = found
            phase = .loaded
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed(error.localizedDescription)
        }
    }
}

private struct SignedOutView: View {
    @Environment(AuthService.self) private var auth

    var body: some View {
        VStack(spacing: Theme.Space.lg) {
            EmptyHint(symbol: "person.crop.circle", title: "Sign in to YouTube Music", detail: "Lilt uses your account and Premium subscription.")
            Button("Sign In") { auth.isPresentingLogin = true }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct EmptyHint: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: Theme.Space.sm) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.callout.weight(.medium))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Theme.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
