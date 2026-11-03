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
        // The content switches type (home, spinner, results). Inside a fixed container the bar
        // and its text field keep their identity across that switch; attached straight to the
        // conditional, they were rebuilt on every phase change, and a rebuilt field re-focuses
        // and selects all its text, eating the next character typed.
        ZStack { content }
            // A safe-area *bar* (not inset): results scroll beneath it and the system draws its
            // progressive scroll-edge blur under the field.
            .safeAreaBar(edge: .top, spacing: 0) {
                // Signed out there is nothing to search or revisit, so no controls at all.
                if auth.isSignedIn {
                    HStack(spacing: Theme.Space.sm) {
                        // The library button itself is drawn by the column, static above the pages
                        // (it becomes the back chevron); this just keeps its room.
                        Color.clear.frame(width: Theme.Size.headerRow, height: Theme.Size.headerRow)
                        SearchField(text: $navigation.query)
                        RecentsMenu()
                    }
                    .padding(.top, Theme.Space.panelInset)
                    .padding(.horizontal, Theme.Space.panelInset)
                    .padding(.bottom, Theme.Space.sm)
                    .headerBackdrop(visibility: Self.backdropVisibility(forScrollOffset: scrollOffset))
                }
            }
            .task(id: navigation.query) { await search() }
    }

    @ViewBuilder
    private var content: some View {
        if !auth.isSignedIn {
            SignedOutView()
        } else {
            // Results that land quickly come straight in; only a slow search shows the skeleton.
            // A new query typed over results keeps them on screen until its own arrive.
            DelayedPlaceholder(isLoading: phase == .loading) {
                switch phase {
                case .idle:
                    HomeScreen(scrollOffset: $scrollOffset)
                case .loading:
                    EmptyView()
                case .failed(let message):
                    EmptyHint(symbol: "exclamationmark.triangle", title: "Something went wrong", detail: message)
                case .loaded where results.isEmpty:
                    EmptyHint(symbol: "music.note", title: "Nothing found", detail: "Try a different search.")
                        .onAppear { scrollTracker.report(remainingBelow: 0, for: ScrollTracker.searchKey) }
                case .loaded:
                    resultsList
                }
            } placeholder: {
                ScrollView { Skeleton.Rows(count: 7, header: true) }
                    .scrollDisabled(true)
            }
        }
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                // Section by section, as the root comes back under a staggering transition.
                if let top = results.top {
                    CollapsibleSection(title: "Top result", scope: "search", items: [top]) { BrowseRow(item: $0) }
                        .entrance(.row(0))
                }
                if !results.songs.isEmpty {
                    CollapsibleSection(title: "Songs", scope: "search", items: results.songs) { TrackRows(tracks: results.songs, only: $0) }
                        .entrance(.row(1))
                }
                browseSection("Artists", results.artists).entrance(.row(2))
                browseSection("Albums", results.albums).entrance(.row(3))
                browseSection("Playlists", results.playlists).entrance(.row(4))
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
            scrollTracker.report(remainingBelow: metrics.contentHeight - metrics.visibleHeight - metrics.offset, for: ScrollTracker.searchKey)
        }
    }

    @ViewBuilder
    private func browseSection(_ title: String, _ items: [BrowseItem]) -> some View {
        if !items.isEmpty {
            CollapsibleSection(title: title, scope: "search", items: items) { BrowseRow(item: $0) }
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

/// The welcome when nobody is signed in: the app's own icon, a line on what Lilt is, and the
/// one thing to do.
private struct SignedOutView: View {
    @Environment(AuthService.self) private var auth

    /// The icon from the bundle, not `NSApp.applicationIconImage`, which the Dock tile replaces
    /// with the cover while something plays.
    private static let icon = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)

    var body: some View {
        VStack(spacing: Theme.Space.lg) {
            Image(nsImage: Self.icon)
                .resizable()
                .frame(width: 96, height: 96)
            VStack(spacing: Theme.Space.sm) {
                Text("Your YouTube Music, in Lilt")
                    .font(.title3.weight(.semibold))
                Text("Sign in with your Google account to access your library, playlists and music. A Premium subscription is required.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            Button("Sign In") { auth.isPresentingLogin = true }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
        }
        .padding(.horizontal, Theme.Space.xl)
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
