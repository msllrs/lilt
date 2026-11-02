import SwiftUI

/// Your YouTube Music library: playlists, saved albums and followed artists.
struct LibraryScreen: View {
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
    @State private var content = LibraryContent()
    @State private var account: AccountInfo?
    @State private var scrollOffset: CGFloat = 0

    init() {
        // Render the cached library immediately; the task refreshes if the cache is stale.
        let music = MainActor.assumeIsolated { AppDelegate.shared?.music }
        if let cached = MainActor.assumeIsolated({ music?.cachedLibrary }) {
            _content = State(initialValue: cached)
            _phase = State(initialValue: .loaded)
        }
        _account = State(initialValue: MainActor.assumeIsolated { music?.cachedAccount })
    }

    var body: some View {
        body_
            .safeAreaBar(edge: .top, spacing: 0) { header }
            .task(id: music.accountGeneration) { await load() }
            .onChange(of: navigation.refreshRequest) { _, _ in
                if navigation.path.last?.id == NavigationModel.library.id { Task { await load(refresh: true) } }
            }
    }

    private var header: some View {
        let centred = ArtworkStyle.shared.centredLibraryTitle
        return HStack(spacing: Theme.Space.sm) {
            // Slot for the back button, which the navigation column draws statically on top.
            Color.clear.frame(width: Theme.Size.headerRow, height: Theme.Size.headerRow)
            if centred { Spacer(minLength: 0) }
            Text("Library")
                .font(centred ? .body.weight(.medium) : .body)
            Spacer(minLength: 0)
            // Centred: the avatar's slot is always there, so the title sits between equal weights.
            if let account { accountMenu(account) } else if centred { Color.clear.frame(width: Theme.Size.headerRow, height: Theme.Size.headerRow) }
        }
        .frame(height: Theme.Size.headerRow)
        .padding(.top, Theme.Space.panelInset)
        .padding(.horizontal, Theme.Space.panelInset)
        .padding(.bottom, Theme.Space.sm)
        .headerBackdrop(visibility: Self.backdropVisibility(forScrollOffset: scrollOffset))
    }

    /// A library that lands quickly comes straight in; only a slow one shows the skeleton first.
    private var body_: some View {
        DelayedPlaceholder(isLoading: phase == .loading) {
            switch phase {
            case .loading:
                EmptyView()
            case .failed(let message):
                EmptyHint(symbol: "exclamationmark.triangle", title: "Couldn't load your library", detail: message)
            case .loaded where content.isEmpty:
                EmptyHint(symbol: "books.vertical", title: "Nothing saved yet", detail: "Albums, playlists and artists you save on YouTube Music appear here.")
            case .loaded:
                list
            }
        } placeholder: {
            ScrollView { Skeleton.Rows(count: 7, header: true) }
                .scrollDisabled(true)
        }
    }

    /// How many rows exist so far, across the three sections in order. The library changes
    /// rarely and is bounded, so its rows are built once and kept: a lazy stack built them as
    /// they reached the viewport, which a fast scroll outran, and rebuilt whatever it had let
    /// go on the way back. Building them all at once was a pause on arrival instead, so they
    /// come in slices: a screenful on the first frame, then more every frame until done, below
    /// what is on screen.
    @State private var built = 0
    private static let firstSlice = 18
    private static let slice = 10

    private var rowCount: Int { content.playlists.count + content.albums.count + content.artists.count }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                section("Playlists", content.playlists, limit: built)
                section("Albums", content.albums, limit: built - content.playlists.count)
                section("Artists", content.artists, limit: built - content.playlists.count - content.albums.count)
            }
            .padding(.horizontal, Theme.Space.rowInset)
            .padding(.bottom, Theme.Space.sm)
        }
        .task(id: rowCount) {
            // Each slice lands without animation; a row folding in as it is built would read as
            // the list loading.
            var still = Transaction()
            still.disablesAnimations = true
            if built == 0 { withTransaction(still) { built = min(Self.firstSlice, rowCount) } }
            while built < rowCount {
                try? await Task.sleep(for: .milliseconds(16))
                guard !Task.isCancelled else { return }
                withTransaction(still) { built = min(built + Self.slice, rowCount) }
            }
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
            scrollTracker.report(remainingBelow: metrics.remainingBelow, for: NavigationModel.library.id)
        }
    }

    /// The avatar of the account this library belongs to; click to see or switch accounts.
    private func accountMenu(_ account: AccountInfo) -> some View {
        Menu {
            Section {
                Label("\(account.name) — \(account.email)", systemImage: "checkmark")
            }
            if !account.alternatives.isEmpty {
                Section("Switch to") {
                    ForEach(Array(account.alternatives.enumerated()), id: \.offset) { _, alt in
                        Button(alt.name) {
                            music.switchAccount(pageId: alt.pageId)
                        }
                    }
                }
            }
            Section {
                Button("Sign Out…", role: .destructive) { AppDelegate.shared?.signOut() }
            }
        } label: {
            ArtworkView(url: account.photoURL, size: Theme.Size.headerArtwork, radius: Theme.Size.headerArtwork / 2, context: .avatar)
                .frame(width: Theme.Size.headerRow, height: Theme.Size.headerRow)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(account.email)
    }

    /// Empty sections still show, with YouTube's own explanation, so it's clear the page loaded
    /// and the account simply has nothing saved there.
    @ViewBuilder
    private func section(_ title: String, _ items: [BrowseItem], limit: Int) -> some View {
        CollapsibleSection(title: title, scope: "library", items: items, limit: max(0, limit)) { BrowseRow(item: $0) } empty: {
            Text(title == "Albums" ? "Albums you save to your library will show here."
                : title == "Artists" ? "Artists will show here when you save their music."
                : "Playlists you create or save will show here.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, Theme.Space.rowPadding)
                .padding(.vertical, Theme.Space.xs)
        }
    }

    /// A `refresh` (⌘R) fetches even a fresh library, eases a change in, and keeps the rows on
    /// screen if it fails.
    private func load(refresh: Bool = false) async {
        do {
            async let who = music.account()
            let fresh = try await music.library(forceRefresh: refresh)
            if refresh { notices?.postRefresh(RefreshOutcome(old: content, new: fresh), of: "Library") }
            withAnimation(refresh ? Theme.Motion.standard : nil) { content = fresh }
            if let fresh = try? await who { account = fresh }
            phase = .loaded
        } catch is CancellationError {
        } catch {
            if !(refresh && phase == .loaded) { phase = .failed(error.localizedDescription) }
            if refresh { notices?.postRefresh(.failed, of: "Library") }
        }
    }
}
