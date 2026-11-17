import SwiftUI

struct SearchScreen: View {
    @Environment(AuthService.self) private var auth
    @Environment(YTMusicClient.self) private var music
    @Environment(NavigationModel.self) private var navigation
    @Environment(ScrollTracker.self) private var scrollTracker
    @Environment(\.hidesUnavailableSongs) private var hidesUnavailable

    private enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    @State private var phase: Phase = .idle
    @State private var results = SearchResults()
    @State private var scroll = ListScroll()
    /// Bumped by Try Again, to run the same search once more.
    @State private var attempt = 0

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
                    .headerBackdrop(visibility: scroll.backdropVisibility)
                }
            }
            .task(id: SearchRequest(query: navigation.query, attempt: attempt)) { await search() }
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
                    HomeScreen(scroll: $scroll)
                case .loading:
                    EmptyView()
                case .failed(let message):
                    EmptyHint(symbol: "exclamationmark.triangle", title: "Something went wrong", detail: message) { attempt += 1 }
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
        let songs = SongShelf(results.songs, hidingUnavailable: hidesUnavailable)
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                // Section by section, as the root comes back under a staggering transition.
                if let top = results.top {
                    CollapsibleSection(title: "Top result", scope: "search", items: [top]) { BrowseRow(item: $0) }
                        .entrance(.row(0))
                }
                if !results.songs.isEmpty {
                    CollapsibleSection(title: "Songs", scope: "search", items: results.songs) { songs.row(for: $0) }
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

    @ViewBuilder
    private func browseSection(_ title: String, _ items: [BrowseItem]) -> some View {
        if !items.isEmpty {
            CollapsibleSection(title: title, scope: "search", items: items) { BrowseRow(item: $0) }
        }
    }

    private struct SearchRequest: Equatable {
        var query: String
        var attempt: Int
    }

    private func search() async {
        let trimmed = navigation.query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { phase = .idle; return }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        // Results on screen stay there until the new ones land; a failure gives way at once.
        if phase != .loaded { phase = .loading }
        do {
            let found = try await music.search(trimmed)
            guard !Task.isCancelled else { return }
            results = found
            phase = .loaded
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled else { return }
            Diagnostics.shared.record(.screen, "Search couldn't load: \(error)")
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
    /// For a screen that couldn't load: a Try Again button under the message, so the way back
    /// is where the failure is rather than ⌘R.
    var retry: (() -> Void)? = nil

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
            if let retry {
                Button("Try Again", action: retry)
                    .buttonStyle(.glass)
                    .padding(.top, Theme.Space.xs)
            }
        }
        .padding(.horizontal, Theme.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
