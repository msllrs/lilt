import SwiftUI

/// Your YouTube Music library: playlists, saved albums and followed artists.
struct LibraryScreen: View {
    @Environment(YTMusicClient.self) private var music
    @Environment(ScrollTracker.self) private var scrollTracker
    @Environment(NavigationModel.self) private var navigation
    @Environment(NoticeCenter.self) private var notices: NoticeCenter?
    @Environment(CollapsedSections.self) private var collapsedSections
    @AppStorage(LibraryShelf.previewKey) private var storedPreview = LibraryShelf.standardPreview

    private enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    @State private var phase: Phase = .loading
    @State private var content = LibraryContent()
    @State private var account: AccountInfo?
    @State private var scrollOffset: CGFloat = 0

    /// `music` is the client in the environment, which the app's is unless a test hosts its own.
    init(music: YTMusicClient? = nil) {
        // Render the cached library immediately; the task refreshes if the cache is stale.
        let music = music ?? MainActor.assumeIsolated { AppDelegate.shared?.music }
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
                EmptyHint(symbol: "exclamationmark.triangle", title: "Couldn't load your library", detail: message) {
                    phase = .loading
                    Task { await load() }
                }
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

    /// Lazy, like every other list: only the rows on screen are built, as they come into view.
    /// A saved library built whole, even in slices a frame apart, held the main thread for most
    /// of a second after the page arrived (see LibraryArrivalTests); a row takes about 2ms to
    /// build, so even a fast fling builds no more than two or three a frame.
    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(LibraryShelf.allCases, id: \.self) { section($0) }
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
    /// The first few of a shelf, and See All for the rest on a page of its own.
    @ViewBuilder
    private func section(_ shelf: LibraryShelf) -> some View {
        let title = shelf.title
        let all = shelf.items(in: content)
        let preview = LibraryShelf.preview(stored: storedPreview)
        let items = Array(all.prefix(preview))
        // Rows come in one by one when the library is pushed under a staggering transition.
        let first = LibraryShelf.allCases.prefix { $0 != shelf }.reduce(0) { $0 + min($1.items(in: content).count, preview + 1) }
        let order = Dictionary(items.enumerated().map { ($1.id, first + $0) }, uniquingKeysWith: { a, _ in a })
        CollapsibleSection(title: title, scope: "library", items: items) { BrowseRow(item: $0).entrance(.row(order[$0.id] ?? .max)) } empty: {
            Text(title == "Albums" ? "Albums you save to your library will show here."
                : title == "Artists" ? "Artists will show here when you save their music."
                : "Playlists you create or save will show here.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, Theme.Space.rowPadding)
                .padding(.vertical, Theme.Space.xs)
        }
        if all.count > items.count, !collapsedSections.isCollapsed("library/\(title)") {
            SeeAllRow(shelf: shelf, count: all.count)
                .entrance(.row(first + items.count))
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
            Diagnostics.shared.record(.screen, "Library couldn't load: \(error)")
            if !(refresh && phase == .loaded) { phase = .failed(error.localizedDescription) }
            if refresh { notices?.postRefresh(.failed, of: "Library") }
        }
    }
}
