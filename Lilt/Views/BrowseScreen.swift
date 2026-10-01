import SwiftUI

/// An artist, album or playlist page.
struct BrowseScreen: View {
    @Environment(YTMusicClient.self) private var music
    @Environment(PlayerService.self) private var player
    @Environment(\.dismiss) private var dismiss

    let item: BrowseItem

    private enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    @State private var phase: Phase = .loading
    @State private var page: BrowsePage?
    /// How far the hero has scrolled away, 0 (at rest) to 1 (collapsed into the header).
    @State private var collapse: CGFloat = 0
    @State private var scrollOffset: CGFloat = 0
    @State private var isHoveringCompactArtwork = false

    /// Scroll distance over which the hero hands off to the compact header.
    private static let collapseDistance: CGFloat = 150

    var body: some View {
        content
            .safeAreaBar(edge: .top, spacing: 0) { navigationHeader }
            .task(id: item.id) { await load() }
            .toolbar(.hidden)
    }

    /// Back button, plus a compact artwork/title/artist that fades in as the hero scrolls out.
    private var navigationHeader: some View {
        HStack(spacing: Theme.Space.sm) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("[", modifiers: .command)

            if let page {
                HStack(spacing: Theme.Space.sm) {
                    compactArtwork(page)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(page.item.title)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                        if !page.item.subtitle.isEmpty {
                            Text(page.item.subtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
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

    /// The compact artwork doubles as a play button once the hero's own Play has scrolled away.
    private func compactArtwork(_ page: BrowsePage) -> some View {
        let isArtist = page.item.kind == .artist
        let radius: CGFloat = isArtist ? 14 : 6
        return Button {
            player.play(page.tracks, startingAt: 0)
        } label: {
            ArtworkView(url: page.item.artworkURL, size: 28, radius: radius)
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(.black.opacity(0.45))
                        .overlay {
                            Image(systemName: "play.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .opacity(isHoveringCompactArtwork ? 1 : 0)
                }
        }
        .buttonStyle(.plain)
        .disabled(page.tracks.isEmpty)
        .onHover { hovering in
            withAnimation(Theme.Motion.quick) { isHoveringCompactArtwork = hovering }
        }
        .help("Play")
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            EmptyHint(symbol: "exclamationmark.triangle", title: "Couldn't load", detail: message)
        case .loaded:
            if let page { pageBody(page) }
        }
    }

    private func pageBody(_ page: BrowsePage) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                header(page)
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
            .padding(.bottom, Theme.Space.sm)
        }
        .scrollIndicators(.never)
        .scrollEdgeEffectStyle(.soft, for: .all)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, offset in
            scrollOffset = offset
            // Smoothstep so the hand-off eases in and out instead of snapping at the ends.
            let t = min(max(offset / Self.collapseDistance, 0), 1)
            collapse = t * t * (3 - 2 * t)
        }
    }

    private func header(_ page: BrowsePage) -> some View {
        VStack(spacing: Theme.Space.md) {
            ArtworkView(
                url: page.item.artworkURL,
                size: 140,
                radius: page.item.kind == .artist ? 70 : Theme.Radius.standalone
            )
            .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
            VStack(spacing: 2) {
                Text(page.item.title)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                if !page.item.subtitle.isEmpty {
                    Text(page.item.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
            if !page.tracks.isEmpty {
                Button {
                    player.play(page.tracks, startingAt: 0)
                } label: {
                    Label("Play", systemImage: "play.fill")
                        .font(.callout.weight(.medium))
                        .padding(.horizontal, Theme.Space.sm)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Space.sm)
        .padding(.bottom, Theme.Space.sm)
        // The hero scrolls away naturally; fading and shrinking it sells the hand-off.
        .opacity(1 - collapse)
        .scaleEffect(1 - 0.1 * collapse, anchor: .top)
    }

    private func load() async {
        do {
            page = try await music.page(for: item)
            phase = .loaded
        } catch is CancellationError {
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}
