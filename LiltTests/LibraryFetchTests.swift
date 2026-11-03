import Foundation
import Testing
@testable import Lilt

/// The library's feeds, when the cached copy is stale: hovering the library button fetches
/// them, and opening the library fetches them too, a moment later, while the hover's fetch is
/// still on its way.
@MainActor
struct LibraryFetchTests {
    /// The four feeds the library is made of, each answering after a while, as the network does.
    private func client(fetched: @escaping (String) -> Void) -> YTMusicClient {
        YTMusicClient(auth: AuthService(), fetchPage: { browseId in
            fetched(browseId)
            try await Task.sleep(for: .milliseconds(100))
            return JSONObject(value: [:])
        }, persists: false, fetchAccount: { nil })
    }

    /// The open joins the hover's fetch rather than starting its own: every feed is fetched,
    /// parsed on the main actor and written to disk once. Measured, they were fetched twice.
    @Test func openingTheLibraryDuringTheHoversFetchFetchesItOnce() async throws {
        var fetches: [String] = []
        let music = client { fetches.append($0) }
        let hover = Task { try await music.library() }
        try await Task.sleep(for: .milliseconds(20))
        let opened = try await music.library()
        let hovered = try await hover.value
        #expect(fetches.sorted() == ["FEmusic_library_corpus_artists", "FEmusic_library_corpus_track_artists", "FEmusic_liked_albums", "FEmusic_liked_playlists"],
                "fetched \(fetches.count) feeds: \(fetches.sorted())")
        #expect(opened == hovered)
    }

    /// A refresh asked for (⌘R) still fetches, even with a fetch on its way.
    @Test func aRefreshFetchesEvenDuringAnotherFetch() async throws {
        var fetches = 0
        let music = client { _ in fetches += 1 }
        let hover = Task { try await music.library() }
        try await Task.sleep(for: .milliseconds(20))
        _ = try await music.library(forceRefresh: true)
        _ = try await hover.value
        #expect(fetches == 8)
    }

    /// Once a fetch has landed, the fresh copy is served without asking again.
    @Test func aFreshLibraryIsServedFromTheCache() async throws {
        var fetches = 0
        let music = client { _ in fetches += 1 }
        _ = try await music.library()
        _ = try await music.library()
        #expect(fetches == 4)
    }
}
