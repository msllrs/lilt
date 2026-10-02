import SwiftUI

/// An artist, album or playlist page.
struct BrowseScreen: View {
    @Environment(YTMusicClient.self) private var music
    @Environment(PlayerService.self) private var player
    @Environment(NavigationModel.self) private var navigation
    @Environment(ScrollTracker.self) private var scrollTracker

    let item: BrowseItem

    private enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    @State private var phase: Phase = .loading
    @State private var page: BrowsePage?
    /// How far the hero has scrolled out, 0 (at rest) to 1 (fully gone). Drives its fade.
    @State private var heroFade: CGFloat = 0
    /// Compact header visibility, 0 to 1. Comes in over the second half of the hero's travel.
    @State private var collapse: CGFloat = 0
    @State private var scrollOffset: CGFloat = 0
    @State private var heroHeight: CGFloat = 280
    /// Extra bottom padding that guarantees enough scroll range for the hero to hand off fully.
    @State private var extraBottom: CGFloat = 0
    @State private var isHoveringCompactArtwork = false

    var body: some View {
        content
            .safeAreaBar(edge: .top, spacing: 0) { navigationHeader }
            .task(id: item.id) { await load() }
    }

    /// Back button, plus a compact artwork/title/artist that fades in as the hero scrolls out.
    private var navigationHeader: some View {
        HStack(spacing: Theme.Space.sm) {
            // Slot for the back button, which the navigation column draws statically on top.
            Color.clear.frame(width: 28, height: 28)

            if let page = page ?? Optional(BrowsePage(item: item)) {
                HStack(spacing: Theme.Space.sm) {
                    compactArtwork(page)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(page.item.title)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
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
        }
        .padding(.top, Theme.Space.panelInset)
        .padding(.horizontal, Theme.Space.panelInset)
        .padding(.bottom, Theme.Space.sm)
        .headerBackdrop(visibility: Self.backdropVisibility(forScrollOffset: scrollOffset))
    }

    private var playCast: PlayCastStyle { ArtworkStyle.shared.playCast }

    /// The hero artwork's dominant colour, for casting onto the controls beneath it.
    private func artworkCast(_ page: BrowsePage) -> Color? {
        guard let url = page.item.artworkURL else { return nil }
        return ImageCache.shared.tint(for: url, saturationBoost: playCast.saturation)
    }

    /// A soft wash of the artwork colour inside the capsule, strongest at the top edge.
    @ViewBuilder
    private func castGlow(_ cast: Color?) -> some View {
        if let cast, playCast.glowOpacity > 0 {
            Capsule()
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: cast.opacity(playCast.glowOpacity), location: 0),
                            .init(color: .clear, location: playCast.glowHeight),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .blur(radius: playCast.glowBlur)
                .clipShape(Capsule())
                .allowsHitTesting(false)
        }
    }

    /// On album pages the subtitle is the artist; link it.
    private func pageArtist(_ page: BrowsePage) -> BrowseItem? {
        guard page.item.kind == .album, let artistId = page.artistId else { return nil }
        return BrowseItem(id: artistId, kind: .artist, title: page.item.subtitle, subtitle: "Artist", artworkURL: nil)
    }

    /// The compact artwork doubles as a play button once the hero's own Play has scrolled away.
    private func compactArtwork(_ page: BrowsePage) -> some View {
        let isArtist = page.item.kind == .artist
        let radius: CGFloat = isArtist ? 14 : Theme.Radius.artwork(28)
        return Button {
            player.play(page.tracks, startingAt: 0)
        } label: {
            ArtworkView(url: page.item.artworkURL, size: 28, radius: radius, context: .header)
                .playOverlay(isVisible: isHoveringCompactArtwork, radius: radius, size: 28)
        }
        .buttonStyle(.plain)
        .disabled(page.tracks.isEmpty)
        .onHover { isHoveringCompactArtwork = $0 }
        .help("Play")
    }

    /// The header renders straight away from what the tapped row already knew; only the body
    /// waits for the network.
    private var content: some View {
        pageBody(page ?? BrowsePage(item: item))
    }

    private func pageBody(_ page: BrowsePage) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                header(page)
                switch phase {
                case .loading:
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                        .padding(.top, Theme.Space.xl)
                case .failed(let message):
                    EmptyHint(symbol: "exclamationmark.triangle", title: "Couldn't load", detail: message)
                        .padding(.top, Theme.Space.xl)
                case .loaded:
                    EmptyView()
                }
                if !page.tracks.isEmpty {
                    SectionHeader(page.item.kind == .artist ? "Top songs" : "Tracks")
                    TrackRows(tracks: page.tracks)
                    if let allSongsId = page.allSongsId {
                        BrowseRow(item: BrowseItem(
                            id: allSongsId, kind: .playlist, title: "All songs",
                            subtitle: page.item.title, artworkURL: page.item.artworkURL
                        ))
                    }
                }
                ForEach(page.sections) { section in
                    SectionHeader(section.title)
                    ForEach(section.items) { BrowseRow(item: $0) }
                }
            }
            .padding(.horizontal, Theme.Space.rowInset)
            .padding(.bottom, Theme.Space.sm + extraBottom)
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
            scrollTracker.report(remainingBelow: metrics.remainingBelow, for: item.id)

            // How far the list could scroll on its own, before our padding.
            let naturalRange = metrics.contentHeight - extraBottom - metrics.visibleHeight
            guard naturalRange > 0 else {
                // Fits without scrolling: nothing moves, so nothing collapses.
                extraBottom = 0
                heroFade = 0
                collapse = 0
                return
            }
            // Guarantee a full hero's worth of travel so the hand-off can never stall halfway
            // with a half-faded hero and a half-visible compact header.
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

    private func header(_ page: BrowsePage) -> some View {
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
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                if !page.item.subtitle.isEmpty {
                    ArtistLink(name: page.item.subtitle, item: pageArtist(page), font: .caption)
                }
            }
            if !page.tracks.isEmpty {
                Button {
                    player.play(page.tracks, startingAt: 0)
                } label: {
                    Label("Play", systemImage: "play.fill")
                        .font(.callout.weight(.semibold))
                        .padding(.horizontal, Theme.Space.lg + Theme.Space.xs)
                        .padding(.vertical, Theme.Space.sm + Theme.Space.xs)
                        // Glass and rim live on the label so the press scale moves the whole capsule.
                        // The cover above casts its colour onto the glass, a wash along the top
                        // edge, and the lit rim.
                        .glassEffect(.regular.tint(artworkCast(page)?.opacity(playCast.tintOpacity)).interactive(), in: .capsule)
                        .overlay { castGlow(artworkCast(page)) }
                        .glassEdge(Capsule(), cast: artworkCast(page), castMix: playCast.rimMix)
                        .contentShape(Capsule())
                }
                .buttonStyle(.pressable)
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

    private func load() async {
        do {
            var loaded = try await music.page(for: item)
            page = loaded
            phase = .loaded
            // Fill short album pages out with the artist's other releases and related artists
            // rather than leaving dead space under the tracks.
            if loaded.item.kind == .album, let artistId = loaded.artistId {
                let artist = BrowseItem(id: artistId, kind: .artist, title: loaded.item.subtitle, subtitle: "Artist", artworkURL: nil)
                if let artistPage = try? await music.page(for: artist), !Task.isCancelled {
                    loaded.sections.append(contentsOf: Self.relatedSections(from: artistPage, excluding: loaded))
                    withAnimation(Theme.Motion.standard) { page = loaded }
                }
            }
        } catch is CancellationError {
        } catch {
            phase = .failed(error.localizedDescription)
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
