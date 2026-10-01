import Foundation
import Observation

/// Typed YouTube Music operations on top of `InnerTubeClient`.
@MainActor
@Observable
final class YTMusicClient {
    /// InnerTube search filter for songs only.
    private static let songsFilter = "EgWKAQIIAWoMEA4QChADEAQQCRAF"

    @ObservationIgnored private let client: InnerTubeClient

    init(auth: AuthService) {
        client = InnerTubeClient(auth: auth)
    }

    func searchSongs(_ query: String) async throws -> [Track] {
        let json = try await client.post("search", body: ["query": query, "params": Self.songsFilter])
        return SearchParser.tracks(from: json)
    }
}
