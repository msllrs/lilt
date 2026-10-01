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
    private static let homeTTL: TimeInterval = 5 * 60

    init(auth: AuthService) {
        client = InnerTubeClient(auth: auth)
    }

    func search(_ query: String) async throws -> SearchResults {
        async let songsResponse = client.post("search", body: ["query": query, "params": Self.songsFilter])
        async let mixedResponse = client.post("search", body: ["query": query])
        var results = SearchParser.browseItems(from: try await mixedResponse.value)
        results.songs = SearchParser.tracks(from: try await songsResponse.value)
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
        return sections
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
        return page
    }
}
