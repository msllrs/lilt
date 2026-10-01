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

    func page(for item: BrowseItem) async throws -> BrowsePage {
        if let cached = pageCache[item.id] { return cached }
        let response = try await client.post("browse", body: ["browseId": item.id])
        let page = SearchParser.browsePage(from: response.value, for: item)
        pageCache[item.id] = page
        return page
    }
}
