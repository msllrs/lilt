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

    var body: some View {
        VStack(spacing: 0) {
            navigationHeader
            content
        }
        .task(id: item.id) { await load() }
        .toolbar(.hidden)
    }

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
            Text(page?.item.title ?? item.title)
                .font(.callout.weight(.medium))
                .lineLimit(1)
            Spacer()
        }
        .padding(.top, Theme.Space.panelInset)
        .padding(.horizontal, Theme.Space.panelInset)
        .padding(.bottom, Theme.Space.sm)
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
        .scrollEdgeEffectStyle(.soft, for: .bottom)
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
