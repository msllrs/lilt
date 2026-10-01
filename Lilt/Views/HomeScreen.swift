import SwiftUI

/// Your YouTube Music home feed, shown when the search field is empty.
struct HomeScreen: View {
    @Environment(YTMusicClient.self) private var music

    private enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    @State private var phase: Phase = .loading
    @State private var sections: [HomeSection] = []
    @Binding var scrollOffset: CGFloat

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                EmptyHint(symbol: "exclamationmark.triangle", title: "Couldn't load Home", detail: message)
            case .loaded where sections.isEmpty:
                EmptyHint(symbol: "magnifyingglass", title: "Search YouTube Music", detail: "Songs, artists, albums and playlists.")
            case .loaded:
                feed
            }
        }
        .task { await load() }
    }

    private var feed: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(sections) { section in
                    SectionHeader(section.title)
                    let tracks = section.tracks
                    ForEach(section.items) { item in
                        switch item {
                        case .track(let track):
                            TrackRows(tracks: tracks, only: track)
                        case .browse(let browse):
                            BrowseRow(item: browse)
                        }
                    }
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
        }
    }

    private func load() async {
        do {
            sections = try await music.home()
            phase = .loaded
        } catch is CancellationError {
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}
