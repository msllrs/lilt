import AppKit
import SwiftUI

/// An artist, album or playlist page.
struct BrowseScreen: View {
    @Environment(YTMusicClient.self) private var music
    @Environment(PlayerService.self) private var player
    @Environment(NavigationModel.self) private var navigation
    @Environment(ScrollTracker.self) private var scrollTracker
    @Environment(\.colorScheme) private var colorScheme

    let item: BrowseItem

    private enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    @State private var phase: Phase = .loading
    @State private var page: BrowsePage?
    /// Holds the skeleton back while a quick page is on its way, and up once it has shown.
    @State private var loadingGate = LoadingGate()

    /// The skeleton's turn: still loading, or loaded while a shown skeleton has yet to have its
    /// minimum time. Through the grace period the skeleton is there but invisible, keeping its
    /// place so the hero and the rows don't move when the content lands.
    private var awaitingContent: Bool { phase == .loading || loadingGate.showsPlaceholder }

    init(item: BrowseItem) {
        self.item = item
        // A page we've already fetched renders on the first frame, no spinner.
        if let cached = MainActor.assumeIsolated({ AppDelegate.shared?.music.cachedPage(for: item) }) {
            _page = State(initialValue: cached)
            _phase = State(initialValue: .loaded)
        }
    }
    /// How far the hero has scrolled out, 0 (at rest) to 1 (fully gone). Drives its fade.
    @State private var heroFade: CGFloat = 0
    /// Compact header visibility, 0 to 1. Comes in over the second half of the hero's travel.
    @State private var collapse: CGFloat = 0
    @State private var scrollOffset: CGFloat = 0
    @State private var heroHeight: CGFloat = 280
    /// Extra bottom padding that guarantees enough scroll range for the hero to hand off fully.
    @State private var extraBottom: CGFloat = 0
    @State private var isHoveringCompactArtwork = false
    @State private var isHoveringHeader = false
    /// Bumped once the cover has loaded, so an accent measured from it is read again (the image
    /// cache isn't observable).
    @State private var coverLoads = 0

    /// Only playlists gain songs elsewhere (a song liked on the phone), so only they refresh:
    /// albums don't change once released and artist pages rarely do.
    private var isRefreshable: Bool { item.kind == .playlist }

    var body: some View {
        // An album's text and glyphs take its cover's colour the way the platter's do, sliding in
        // if the colour lands after the page. The hero and compact header are built here and take
        // it directly; the rows and section headers below read it from the environment.
        InterpolatedColor(pageAccent) { accent in
            let palette = Self.palette(kind: (page ?? BrowsePage(item: item)).item.kind, accent: accent, colorScheme: colorScheme)
            content(palette)
                .safeAreaBar(edge: .top, spacing: 0) { navigationHeader(palette) }
                .environment(\.coverPalette, palette)
        }
        // The cover's light spills down from the top of the page, behind everything.
        .background(alignment: .top) { PageAmbient(url: (page?.item.artworkURL) ?? item.artworkURL) }
        .task(id: item.id) { await load() }
        .loadingGate(loadingGate, isLoading: phase == .loading)
        // ⌘R takes the same path as pulling the list down.
        .onChange(of: navigation.refreshRequest) { _, _ in
            if isRefreshable, navigation.path.last?.id == item.id { Task { await load(announce: true) } }
        }
    }

    /// Back button, plus a compact artwork/title/artist that fades in as the hero scrolls out.
    private func navigationHeader(_ palette: CoverPalette) -> some View {
        HStack(spacing: Theme.Space.sm) {
            // Slot for the back button, which the navigation column draws statically on top.
            Color.clear.frame(width: Theme.Size.headerRow, height: Theme.Size.headerRow)

            if let page = page ?? Optional(BrowsePage(item: item)) {
                HStack(spacing: Theme.Space.sm) {
                    compactArtwork(page)
                    VStack(alignment: .leading, spacing: 0) {
                        MarqueeText(text: page.item.title, isActive: isHoveringHeader, font: .callout.weight(.medium), color: palette.style(\.primary, or: .primary))
                        if !page.item.subtitle.isEmpty {
                            ArtistLink(name: page.item.subtitle, item: pageArtist(page), font: .caption2)
                        }
                    }
                }
                .opacity(collapse)
                .offset(y: (1 - collapse) * 10)
                .allowsHitTesting(collapse > 0.5)
            }
            Spacer()
            pageMenu(page ?? BrowsePage(item: item), palette: palette)
        }
        .frame(height: Theme.Size.headerRow)
        .padding(.top, Theme.Space.panelInset)
        .padding(.horizontal, Theme.Space.panelInset)
        .padding(.bottom, Theme.Space.sm)
        .headerBackdrop(visibility: Self.backdropVisibility(forScrollOffset: scrollOffset))
        .onHover { isHoveringHeader = $0 }
        // The back button sits beside this header; let it catch the artwork's colour as the
        // header arrives. Only the page on top speaks for it, and it lets go when it leaves.
        .onChange(of: collapse, initial: true) { _, _ in publishLeadingCast() }
        .onChange(of: page?.item.artworkURL) { _, _ in publishLeadingCast() }
        .onChange(of: navigation.path.last?.id) { _, _ in publishLeadingCast() }
        // The cover's colours may not be measured yet when the header arrives; publish again once
        // the image is in (also when the page loads and brings a cover the row didn't have).
        .task(id: page?.item.artworkURL ?? item.artworkURL) {
            guard let url = page?.item.artworkURL ?? item.artworkURL else { return }
            _ = await ImageCache.shared.load(url)
            publishLeadingCast()
            coverLoads += 1
        }
        .onDisappear {
            if navigation.path.last?.id == item.id || navigation.path.isEmpty { navigation.leadingCastAmount = 0 }
            if navigation.path.isEmpty { navigation.leadingTintAccent = nil }
        }
    }

    private func publishLeadingCast() {
        guard navigation.path.last?.id == item.id else { return }
        let current = page ?? BrowsePage(item: item)
        navigation.leadingCast = current.item.artworkURL.flatMap { ImageCache.shared.tint(for: $0, saturationBoost: ArtworkStyle.shared.leadingCast.saturation) }
        navigation.leadingCastAmount = Double(collapse)
        // The back button's glyph wears the album's colour like the page's own controls; any
        // other page on top hands it back to plain.
        navigation.leadingTintAccent = pageAccent
    }

    private var playCast: PlayCastStyle { ArtworkStyle.shared.playCast }

    /// Only an album wears its cover's colour: it is one cover with one palette, where a
    /// playlist mixes covers and an artist page has an avatar.
    nonisolated static func wearsCoverTint(_ kind: BrowseKind) -> Bool { kind == .album }

    /// The page's palette: the cover's accent on an album, held to a readable contrast on the
    /// plain panel as the palette is built; every other kind of page gets a plain one, whose
    /// roles fall back to the label colours.
    static func palette(kind: BrowseKind, accent: Color?, colorScheme: ColorScheme) -> CoverPalette {
        CoverPalette(accent: wearsCoverTint(kind) ? accent : nil, colorScheme: colorScheme, surface: .page)
    }

    /// The album cover's own accent, measured as the platter measures the playing song's.
    private var pageAccent: Color? {
        _ = coverLoads
        let current = page ?? BrowsePage(item: item)
        guard Self.wearsCoverTint(current.item.kind), let url = current.item.artworkURL else { return nil }
        return ImageCache.shared.accent(for: url, saturationBoost: ArtworkStyle.shared.palette.accentSaturation)
    }

    /// Liked Music is YouTube's automatic playlist: always in the library, never saved or removed.
    nonisolated static func isLikedMusic(_ item: BrowseItem) -> Bool { item.id == "VLLM" || item.id == "LM" }

    /// A song unliked or removed in Lilt leaves the list at once, without waiting for a refetch.
    private func shownTracks(_ page: BrowsePage) -> [Track] {
        let likedMusic = Self.isLikedMusic(page.item)
        return page.tracks.filter { !music.isRemoved($0) && (!likedMusic || music.isLiked($0) != false) }
    }

    /// Play, save and shuffle all share this height so the row reads as one set of controls.
    static let heroControlHeight: CGFloat = 38
    @Environment(NoticeCenter.self) private var notices: NoticeCenter?
    @State private var isSaving = false
    private var isSaved: Bool { music.isSaved(item) }

    /// A round glass button beside Play, with the same cast. On an album the glyph is the
    /// palette's colour on its container, dimmed while the button can't be used (an explicit
    /// colour doesn't dim itself).
    private func heroRoundButton(symbol: String, help: String, palette: CoverPalette, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                // Glyph swap (bookmark ↔ bookmark.fill): scale, blur and fade in place, like the
                // platter's like and a row's queue button.
                Image(systemName: symbol)
                    .font(.callout.weight(.semibold))
                    .id(symbol)
                    .transition(.blurScale)
            }
            .animation(Theme.Motion.symbol, value: symbol)
            .foregroundStyle(palette.style(disabled ? \.dimControl : \.onContainer, or: .primary))
            .frame(width: Self.heroControlHeight, height: Self.heroControlHeight)
            .modifier(HeroGlass(shape: Circle(), palette: palette))
        }
        .buttonStyle(.pressable)
        .disabled(disabled)
        .help(help)
    }

    private func toggleSaved(_ page: BrowsePage) {
        let target = !isSaved
        isSaving = true
        Task {
            defer { isSaving = false }
            await RowMenu.setSaved(target, page: page, music: music, notices: notices)
        }
    }

    /// The hero artwork's dominant colour, for casting onto the controls beneath it.
    private func artworkCast(_ page: BrowsePage) -> Color? {
        guard let url = page.item.artworkURL else { return nil }
        return ImageCache.shared.tint(for: url, saturationBoost: playCast.saturation)
    }

    /// The page's web address on YouTube Music.
    private func webURL(for page: BrowsePage) -> URL? {
        switch page.item.kind {
        case .artist: URL(string: "https://music.youtube.com/channel/\(page.item.id)")
        case .album: URL(string: "https://music.youtube.com/browse/\(page.item.id)")
        default: page.playlistId.flatMap { URL(string: "https://music.youtube.com/playlist?list=\($0)") }
        }
    }

    /// Opposite the back button: a place for page actions as they arrive.
    private func pageMenu(_ page: BrowsePage, palette: CoverPalette) -> some View {
        Menu {
            // Play and Shuffle Play are the hero's buttons; the page's mix is here.
            if page.item.kind != .library {
                Button(RowAction.startMix.title) { RowMenu.startMix(for: page.item, player: player, music: music, notices: notices) }
                Divider()
            }
            // The same refresh as pulling the list down or ⌘R.
            if isRefreshable {
                Button("Refresh") { Task { await load(announce: true) } }
                Divider()
            }
            Button("Open in YouTube Music") { if let url = webURL(for: page) { NSWorkspace.shared.open(url) } }
            Button("Copy Link") {
                guard let url = webURL(for: page) else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.absoluteString, forType: .string)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .rotationEffect(.degrees(90))
                .foregroundStyle(palette.style(\.control, or: .primary))
                .headerControl()
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More")
    }

    /// On album pages the subtitle is the artist; link it.
    private func pageArtist(_ page: BrowsePage) -> BrowseItem? {
        guard page.item.kind == .album, let artistId = page.artistId else { return nil }
        return BrowseItem(id: artistId, kind: .artist, title: page.item.subtitle, subtitle: "Artist", artworkURL: nil)
    }

    /// True when the track playing right now came from this page.
    /// Only when the queue was started from this page: a track that merely appears in this
    /// playlist, played from elsewhere, doesn't make the playlist "playing".
    private func isPlayingFromPage(_ page: BrowsePage) -> Bool {
        player.current != nil && player.sourceId == page.item.id
    }

    /// The compact artwork doubles as a play button once the hero's own Play has scrolled away,
    /// and becomes a spinning record while this page is the one playing.
    private func compactArtwork(_ page: BrowsePage) -> some View {
        // The same size as the controls beside it (see Theme.Size.headerArtwork).
        let size = Theme.Size.headerArtwork
        let isArtist = page.item.kind == .artist
        let radius: CGFloat = isArtist ? size / 2 : Theme.Radius.artwork(size)
        let playingHere = isPlayingFromPage(page)
        return Button {
            if playingHere { player.togglePlayPause() } else { player.play(page.tracks, startingAt: 0, source: page.item) }
        } label: {
            SpinningArtwork(
                url: page.item.artworkURL,
                size: size,
                restRadius: radius,
                context: .header,
                isDisc: playingHere && !isArtist,
                isSpinning: playingHere && player.isPlaying
            )
            .playOverlay(
                isVisible: isHoveringCompactArtwork,
                symbol: playingHere && player.isPlaying ? "pause.fill" : "play.fill",
                radius: playingHere && !isArtist ? size / 2 : radius,
                size: size
            )
            // The same notes a playing row's disc gives off, scaled to this smaller disc.
            .overlay {
                if playingHere && !isArtist {
                    let scale = size / Theme.Size.rowArtwork
                    NoteEmitterView(isPlaying: player.isPlaying, center: CGPoint(x: 60 * scale, y: 60 * scale), artworkURL: page.item.artworkURL, scale: scale)
                        .frame(width: 120 * scale, height: 120 * scale)
                        .allowsHitTesting(false)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(page.tracks.isEmpty)
        .onHover { isHoveringCompactArtwork = $0 }
        .help("Play")
    }

    /// The header renders straight away from what the tapped row already knew; only the body
    /// waits for the network.
    private func content(_ palette: CoverPalette) -> some View {
        pageBody(page ?? BrowsePage(item: item), palette: palette)
    }

    private func pageBody(_ page: BrowsePage, palette: CoverPalette) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                header(page, palette: palette)
                if awaitingContent {
                    Skeleton.Rows(count: 6, header: true, insetsRows: false)
                        .placeholderShown(loadingGate.showsPlaceholder)
                        .transition(.opacity)
                } else {
                    switch phase {
                    case .failed(let message):
                        EmptyHint(symbol: "exclamationmark.triangle", title: "Couldn't load", detail: message)
                            .padding(.top, Theme.Space.xl)
                    case .loaded where page.tracks.isEmpty && page.sections.isEmpty:
                        // e.g. Liked Music before anything has been liked in YouTube Music.
                        EmptyHint(symbol: "music.note.list", title: "Nothing here yet", detail: "Songs you add on YouTube Music will show up here.")
                            .padding(.top, Theme.Space.xl)
                    case .loaded, .loading:
                        EmptyView()
                    }
                    if !page.tracks.isEmpty {
                        SectionHeader(page.item.kind == .artist ? "Top songs" : "Tracks")
                        TrackRows(tracks: shownTracks(page), source: page.item)
                        if let allSongsId = page.allSongsId {
                            BrowseRow(item: BrowseItem(
                                id: allSongsId, kind: .playlist, title: "All songs",
                                subtitle: page.item.title, artworkURL: page.item.artworkURL
                            ))
                        }
                    }
                    ForEach(page.sections) { section in
                        // The header is this page's; the rows are other albums and artists, with
                        // covers of their own, so they keep the plain colours.
                        CollapsibleSection(title: section.title, scope: "page", items: section.items) { BrowseRow(item: $0).environment(\.coverPalette, nil) }
                    }
                }
            }
            .padding(.horizontal, Theme.Space.rowInset)
            .padding(.bottom, Theme.Space.sm + extraBottom)
        }
        .scrollIndicators(.never)
        .panelScrollEdge()
        .pullToRefresh(isEnabled: isRefreshable) { await load(announce: true) }
        // A scroll that would end part-way through the hero's travel is steered to the nearer
        // end as the fingers lift, in the same motion, so the page never rests with a half-faded
        // hero and a half-visible compact header.
        .scrollTargetBehavior(HeroSnapBehavior(heroHeight: heroHeight, snap: ArtworkStyle.shared.heroSnap))
        .onScrollGeometryChange(for: ScrollMetrics.self) { geometry in
            ScrollMetrics(
                offset: geometry.contentOffset.y + geometry.contentInsets.top,
                contentHeight: geometry.contentSize.height,
                visibleHeight: geometry.containerSize.height - geometry.contentInsets.top - geometry.contentInsets.bottom
            )
        } action: { _, metrics in
            scrollOffset = metrics.offset
            scrollTracker.report(remainingBelow: metrics.remainingBelow, for: item.id)

            // How far the list could scroll on its own, before our padding (negative when the
            // content is shorter than the view).
            let naturalRange = metrics.contentHeight - extraBottom - metrics.visibleHeight
            // Guarantee a full hero's worth of travel whatever the window height, so even a short
            // page can scroll the hero away and the hand-off can never stall halfway. A page that
            // falls short of the view gets the shortfall as well.
            extraBottom = max(0, heroHeight - naturalRange)

            // The hero fades across its own height, so it is gone exactly when it has scrolled
            // under the header and never leaves a blank gap above the tracks.
            let travel = min(max(metrics.offset / max(heroHeight, 1), 0), 1)
            heroFade = Self.smoothstep(travel)
            collapse = Self.smoothstep(min(max((travel - 0.45) / 0.55, 0), 1))
        }
    }


    /// Eases in and out instead of snapping at the ends.
    private static func smoothstep(_ t: CGFloat) -> CGFloat {
        t * t * (3 - 2 * t)
    }

    private func header(_ page: BrowsePage, palette: CoverPalette) -> some View {
        VStack(spacing: Theme.Space.md) {
            ArtworkView(
                url: page.item.artworkURL,
                size: 140,
                radius: page.item.kind == .artist ? 70 : Theme.Radius.standalone,
                context: .hero
            )
            VStack(spacing: 2) {
                Text(page.item.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(palette.style(\.primary, or: .primary))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                if !page.item.subtitle.isEmpty {
                    ArtistLink(name: page.item.subtitle, item: pageArtist(page), font: .caption)
                }
                if let detail = page.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(palette.style(\.tertiary, or: .tertiary))
                }
            }
            if awaitingContent {
                Skeleton.PlayCapsule()
                    .placeholderShown(loadingGate.showsPlaceholder)
                    .transition(.opacity)
            } else if !page.tracks.isEmpty {
                // The cast is interpolated, so a new cover's colour arrives as a change of light
                // over the controls rather than a cut. Save on the left, shuffle on the right,
                // Play between; artists have no library membership, so no save.
                InterpolatedColor(artworkCast(page)) { cast in
                    let glass = palette.casting(cast)
                    HStack(spacing: Theme.Space.sm) {
                        if page.item.kind != .artist, !Self.isLikedMusic(page.item) {
                            heroRoundButton(symbol: isSaved ? "bookmark.fill" : "bookmark", help: isSaved ? "Remove from Library" : "Save to Library", palette: glass, disabled: page.playlistId == nil || isSaving) {
                                toggleSaved(page)
                            }
                        }
                        Button {
                            player.play(page.tracks, startingAt: 0, source: page.item)
                        } label: {
                            Label("Play", systemImage: "play.fill")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(glass.style(\.onContainer, or: .primary))
                                .padding(.horizontal, Theme.Space.lg + Theme.Space.xs)
                                .frame(height: Self.heroControlHeight)
                                .modifier(HeroGlass(shape: Capsule(), palette: glass))
                        }
                        .buttonStyle(.pressable)
                        heroRoundButton(symbol: "shuffle", help: "Shuffle", palette: glass) {
                            player.playShuffled(page.tracks, source: page.item)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Space.sm)
        .padding(.bottom, Theme.Space.sm)
        // The hero scrolls away naturally; fading and shrinking it sells the hand-off.
        .opacity(1 - heroFade)
        .scaleEffect(1 - 0.1 * heroFade, anchor: .top)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heroHeight = $0 }
    }

    /// Fetches the page every time it opens, since it may have changed elsewhere. A cached copy
    /// already on screen stays put while it does: no skeleton, the scroll position kept, and a
    /// changed page eases in. If the fetch fails, the cached copy stays rather than an error.
    /// `announce`: a refresh you asked for, which says how it went in a notice.
    private func load(announce: Bool = false) async {
        let showingCached = phase == .loaded
        let before = page
        if case .failed = phase { phase = .loading }
        do {
            var loaded = try await music.page(for: item)
            guard !Task.isCancelled else { return }
            // Fill short album pages out with the artist's other releases and related artists
            // rather than leaving dead space under the tracks. The artist's page rarely changes,
            // so a copy we have is used as is, and a refetched album keeps those sections
            // instead of dropping them for a moment.
            let artist = pageArtist(loaded)
            if let artist, let artistPage = music.cachedPage(for: artist) {
                loaded.sections.append(contentsOf: Self.relatedSections(from: artistPage, excluding: loaded))
            }
            show(loaded, animated: showingCached)
            if announce { notices?.postRefresh(RefreshOutcome(old: before, new: page), of: loaded.item.title) }
            if let artist, music.cachedPage(for: artist) == nil,
               let artistPage = try? await music.page(for: artist), !Task.isCancelled {
                loaded.sections.append(contentsOf: Self.relatedSections(from: artistPage, excluding: loaded))
                show(loaded, animated: true)
            }
        } catch is CancellationError {
        } catch {
            if !showingCached { phase = .failed(error.localizedDescription) }
            if announce { notices?.postRefresh(.failed, of: item.title) }
        }
    }

    private func show(_ loaded: BrowsePage, animated: Bool) {
        guard loaded != page || phase != .loaded else { return }
        if animated {
            withAnimation(Theme.Motion.standard) { page = loaded; phase = .loaded }
        } else {
            page = loaded
            phase = .loaded
        }
    }

    /// Albums, singles and similar artists from an artist page, renamed for an album context and
    /// without repeating the album being viewed or sections the page already has.
    private static func relatedSections(from artistPage: BrowsePage, excluding album: BrowsePage) -> [BrowseSection] {
        let existing = Set(album.sections.map(\.title))
        var result: [BrowseSection] = []
        for section in artistPage.sections {
            let lower = section.title.lowercased()
            let title: String
            if lower.contains("album") || lower.contains("single") {
                title = "More from \(artistPage.item.title)"
            } else if lower.contains("fans") || lower.contains("similar") || lower.contains("related") {
                title = "Related artists"
            } else {
                continue
            }
            let items = section.items.filter { $0.id != album.item.id }
            guard !items.isEmpty, !existing.contains(title) else { continue }
            if let index = result.firstIndex(where: { $0.title == title }) {
                result[index].items.append(contentsOf: items.filter { item in !result[index].items.contains(where: { $0.id == item.id }) })
            } else {
                result.append(BrowseSection(title: title, items: items))
            }
        }
        return result
    }
}

/// Steers a scroll's projected end point out of the hero's hand-off zone: below the threshold it
/// finishes at the top, above it at the compact header, carried there by the scroll's own
/// deceleration rather than a second animation after it stops.
private struct HeroSnapBehavior: ScrollTargetBehavior {
    let heroHeight: CGFloat
    let snap: HeroSnapStyle

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        guard snap.enabled, heroHeight > 0 else { return }
        // Only a flick is steered, and in the direction it was going. A scroll-wheel step or a
        // slow release has no momentum; steering those by position fights the hand (every tick
        // pulled back to where it came from).
        let velocity = context.velocity.dy
        guard abs(velocity) >= snap.minFlick else { return }
        // The target's origin is in content coordinates: 0 at the top, past the header bar.
        let travel = target.rect.minY / heroHeight
        guard travel > snap.deadZone, travel < 1 - snap.deadZone else { return }
        target.rect.origin.y = velocity > 0 ? heroHeight : 0
    }
}

/// The hero controls' glass: the same surface as the header controls (so the tweak panel's
/// glass settings apply to both), with the cover above casting its colour onto it the way the
/// compact header casts onto the back button: the palette's accent container, its wash and rim,
/// lit from the top here since the cover sits above. Lives on the label so the press scale
/// moves the whole control.
private struct HeroGlass<S: InsettableShape>: ViewModifier {
    let shape: S
    /// The page's palette with the hero's cast as its container seed.
    let palette: CoverPalette

    func body(content: Content) -> some View {
        let style = palette.container
        content
            .modifier(HeaderControlSurface(shape: shape, cornerRadius: BrowseScreen.heroControlHeight / 2, tint: nil))
            .overlay {
                if let wash = palette.containerWash, let rim = palette.containerRim {
                    ZStack {
                        // The wash falls from the top edge, as far as the reach dial says.
                        shape.fill(LinearGradient(
                            stops: [.init(color: wash, location: 0), .init(color: .clear, location: style.washReach)],
                            startPoint: .top, endPoint: .bottom
                        ))
                        // The rim catches the light along the top, fading out below the start. It
                        // runs on the glass highlight's own path, centred on the outline, so the
                        // cast colours that highlight rather than lining the inside of it.
                        shape.inset(by: -0.5).stroke(
                            LinearGradient(stops: [.init(color: rim, location: 0), .init(color: .clear, location: 1 - style.rimStart)], startPoint: .top, endPoint: .bottom),
                            lineWidth: style.rimWidth
                        )
                    }
                    .blendMode(palette.containerBlend)
                    .allowsHitTesting(false)
                }
            }
            .contentShape(shape)
    }
}
