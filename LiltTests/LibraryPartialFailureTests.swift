import Foundation
import Testing
@testable import Lilt

/// The library is four feeds (playlists, albums, and two of artists), and one of them failing
/// leaves the other three on screen: the failed shelf keeps what it showed before, or is empty
/// for now and fetched again next time. Only all four failing is a library that couldn't load.
@MainActor
struct LibraryPartialFailureTests {
    private let album = BrowseItem(id: "MPREb-lateralus", kind: .album, title: "Lateralus", subtitle: "Tool")

    private func client(failing: Set<String>, library: LibraryContent? = nil, fetched: @escaping (String) -> Void = { _ in }) -> YTMusicClient {
        YTMusicClient(auth: AuthService(), fetchPage: { browseId in
            fetched(browseId)
            if failing.contains(browseId) { throw URLError(.timedOut) }
            return JSONObject(value: [:])
        }, persists: false, library: library, fetchAccount: { nil })
    }

    @Test func aFailedShelfKeepsWhatItShowed() async throws {
        let music = client(failing: ["FEmusic_liked_albums"], library: LibraryContent(albums: [album]))
        let library = try await music.library(forceRefresh: true)
        #expect(library.albums == [album], "the albums stay while their feed is down")
        #expect(library.playlists.map(\.id) == ["VLLM"], "the playlists that did load are there")
    }

    @Test func aFailedShelfWithNothingBeforeIsFetchedAgainNextTime() async throws {
        var fetches = 0
        let music = client(failing: ["FEmusic_library_corpus_artists"]) { _ in fetches += 1 }
        let library = try await music.library()
        #expect(library.artists.isEmpty)
        #expect(library.playlists.map(\.id) == ["VLLM"])
        _ = try await music.library()
        #expect(fetches == 8, "a library missing a shelf isn't fresh, so the next ask fetches again")
    }

    @Test func everyFeedFailingIsALibraryThatCouldntLoad() async {
        let music = client(failing: ["FEmusic_liked_playlists", "FEmusic_liked_albums", "FEmusic_library_corpus_track_artists", "FEmusic_library_corpus_artists"])
        await #expect(throws: URLError.self) { try await music.library() }
    }
}
