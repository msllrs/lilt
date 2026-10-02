import Foundation
import Observation

/// Typed YouTube Music operations on top of `InnerTubeClient`, with a small in-memory cache so
/// going back to a page is instant.
@MainActor
@Observable
final class YTMusicClient {
    /// InnerTube search filter for songs only.
    private static let songsFilter = "EgWKAQIIAWoMEA4QChADEAQQCRAF"

    @ObservationIgnored private let client: InnerTubeClient
    @ObservationIgnored private var pageCache: [String: BrowsePage] = [:]
    @ObservationIgnored private var homeCache: (sections: [HomeSection], fetched: Date)?
    @ObservationIgnored private var libraryCache: (content: LibraryContent, fetched: Date)?
    private static let homeTTL: TimeInterval = 5 * 60

    init(auth: AuthService) {
        client = InnerTubeClient(auth: auth)
    }

    func search(_ query: String) async throws -> SearchResults {
        async let songsResponse = client.post("search", body: ["query": query, "params": Self.songsFilter])
        async let mixedResponse = client.post("search", body: ["query": query])
        var results = SearchParser.browseItems(from: try await mixedResponse.value)
        results.songs = SearchParser.tracks(from: try await songsResponse.value)
        ImageCache.shared.prefetch(
            [results.top?.artworkURL] + results.songs.prefix(12).map(\.artworkURL)
                + (results.artists + results.albums + results.playlists).prefix(12).map(\.artworkURL)
        )
        return results
    }

    /// The signed-in home feed, cached briefly so returning to the root is instant.
    func home(forceRefresh: Bool = false) async throws -> [HomeSection] {
        if !forceRefresh, let cached = homeCache, Date.now.timeIntervalSince(cached.fetched) < Self.homeTTL {
            return cached.sections
        }
        let response = try await client.post("browse", body: ["browseId": "FEmusic_home"])
        let sections = SearchParser.home(from: response.value)
        homeCache = (sections, .now)
        ImageCache.shared.prefetch(sections.prefix(3).flatMap { section in
            section.items.prefix(10).map { item -> URL? in
                switch item {
                case .track(let t): t.artworkURL
                case .browse(let b): b.artworkURL
                }
            }
        })
        return sections
    }

    /// The signed-in library: playlists (with Liked Music first), saved albums, and artists.
    func library(forceRefresh: Bool = false) async throws -> LibraryContent {
        if !forceRefresh, let cached = libraryCache, Date.now.timeIntervalSince(cached.fetched) < Self.homeTTL {
            return cached.content
        }
        async let playlists = client.post("browse", body: ["browseId": "FEmusic_liked_playlists"])
        async let albums = client.post("browse", body: ["browseId": "FEmusic_liked_albums"])
        async let artists = client.post("browse", body: ["browseId": "FEmusic_library_corpus_track_artists"])
        // Artists you've subscribed to live under a separate id from artists of saved tracks.
        async let subscriptions = client.post("browse", body: ["browseId": "FEmusic_library_corpus_artists"])
        var content = LibraryContent()
        // The playlists feed includes a "New playlist" tile and the liked-music auto playlist;
        // drop anything without a real playlist id and make sure Liked Music leads.
        var lists = SearchParser.libraryItems(from: try await playlists.value).filter { $0.kind == .playlist && $0.id != "VLSE" }
        if let liked = lists.firstIndex(where: { $0.id == "VLLM" }) {
            lists.insert(lists.remove(at: liked), at: 0)
        } else {
            lists.insert(BrowseItem(id: "VLLM", kind: .playlist, title: "Liked Music", subtitle: "Auto playlist", artworkURL: nil), at: 0)
        }
        content.playlists = lists
        content.albums = SearchParser.libraryItems(from: try await albums.value).filter { $0.kind == .album }
        var seenArtists = Set<String>()
        content.artists = (SearchParser.libraryItems(from: try await artists.value) + SearchParser.libraryItems(from: try await subscriptions.value))
            .filter { $0.kind == .artist && seenArtists.insert($0.id).inserted }
        libraryCache = (content, .now)
        ImageCache.shared.prefetch((content.playlists + content.albums + content.artists).prefix(24).map(\.artworkURL))
        return content
    }

    /// Artist/album links for a track that arrived without them (home feed, radio continuation).
    func links(forVideoId videoId: String) async throws -> TrackLinks? {
        let response = try await client.post("next", body: [
            "videoId": videoId,
            "enablePersistentPlaylistPanel": true,
            "isAudioOnly": true,
        ])
        return SearchParser.links(from: response.value, videoId: videoId)
    }

    func page(for item: BrowseItem) async throws -> BrowsePage {
        if let cached = pageCache[item.id] { return cached }
        let response = try await client.post("browse", body: ["browseId": item.id])
        let page = SearchParser.browsePage(from: response.value, for: item)
        pageCache[item.id] = page
        ImageCache.shared.prefetch(
            [page.item.artworkURL] + page.tracks.prefix(20).map(\.artworkURL)
                + page.sections.flatMap { $0.items.prefix(8).map(\.artworkURL) }
        )
        return page
    }
}
