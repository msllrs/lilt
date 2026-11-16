import Foundation
import Testing
@testable import Lilt

/// Going back to a page you've seen shouldn't cost the whole of it again. Opening Liked Music
/// (about 950 songs in ten pages, 11 MB) fetched every page on each visit, twice a minute
/// apart, unchanged. Now:
/// - a page fetched in the last five minutes shows what's kept and asks for nothing;
/// - after that, only its first page is asked for, and the rest is kept if the first page is
///   as it was (Liked Music is newest first, so a new like shows there); a changed first page
///   gathers the whole list again, as before, whole before it's shown;
/// - a refresh you ask for (⌘R) always gathers the whole list;
/// - liking a song in Lilt makes Liked Music due again, so the song is there next visit;
/// - two asks for the same page at once share one request (hover warming and opening the page
///   doubled requests of up to 1.2 MB in the log).
@MainActor
struct PageRevisitTests {
    private static func row(_ id: String) -> [String: Any] {
        ["musicResponsiveListItemRenderer": [
            "playlistItemData": ["videoId": id],
            "flexColumns": [["musicResponsiveListItemFlexColumnRenderer": ["text": ["runs": [["text": "Song \(id)"]]]]]],
        ]]
    }

    private static func more(_ token: String) -> [String: Any] {
        ["continuationItemRenderer": ["continuationEndpoint": ["continuationCommand": ["token": token, "request": "CONTINUATION_REQUEST_TYPE_BROWSE"]]]]
    }

    /// A first page of `ids` with a token for the rest.
    private static func firstPage(_ ids: [String]) -> JSONObject {
        JSONObject(value: ["contents": ["twoColumnBrowseResultsRenderer": ["secondaryContents": ["sectionListRenderer": ["contents": [[
            "musicPlaylistShelfRenderer": ["playlistId": "LM", "contents": ids.map(row) + [more("page2")]],
        ]]]]]]])
    }

    private static let rest = JSONObject(value: ["onResponseReceivedActions": [["appendContinuationItemsAction": ["continuationItems": [row("v3"), row("v4"), row("v5")]]]]])

    private let liked = BrowseItem(id: "VLLM", kind: .playlist, title: "Liked Music", subtitle: "Auto playlist")

    /// A client counting its requests, its clock set by the test.
    private final class Counts { var pages = 0; var continuations = 0; var firstIds = ["v1", "v2"]; var clock = Date(timeIntervalSinceReferenceDate: 0) }

    private func client(_ counts: Counts, delay: Duration = .zero) -> YTMusicClient {
        let music = YTMusicClient(
            auth: AuthService(),
            fetchPage: { _ in
                counts.pages += 1
                if delay > .zero { try await Task.sleep(for: delay) }
                return Self.firstPage(counts.firstIds)
            },
            fetchContinuation: { _ in counts.continuations += 1; return Self.rest },
            write: { _, _ in JSONObject(value: [:]) },
            persists: false
        )
        music.now = { counts.clock }
        return music
    }

    /// The first visit: the first page, then the rest, as the page screen gathers it.
    private func visit(_ music: YTMusicClient) async throws -> BrowsePage {
        try await music.wholeList(from: music.revisitedPage(for: liked))
    }

    @Test func aPageSeenMomentsAgoAsksForNothing() async throws {
        let counts = Counts()
        let music = client(counts)
        _ = try await visit(music)
        #expect((counts.pages, counts.continuations) == (1, 1))
        counts.clock += 65
        let again = try await music.revisitedPage(for: liked)
        #expect(again.tracks.map(\.id) == ["v1", "v2", "v3", "v4", "v5"], "the whole list, as kept")
        #expect((counts.pages, counts.continuations) == (1, 1), "nothing asked for a minute later")
    }

    @Test func laterAnUnchangedFirstPageKeepsTheRest() async throws {
        let counts = Counts()
        let music = client(counts)
        _ = try await visit(music)
        counts.clock += 6 * 60
        let again = try await music.revisitedPage(for: liked)
        #expect(counts.pages == 2, "the first page is asked for again")
        #expect(counts.continuations == 1, "the rest isn't")
        #expect(again.tracks.map(\.id) == ["v1", "v2", "v3", "v4", "v5"])
        #expect(again.continuation == nil, "and the list is whole, with nothing left to gather")
    }

    @Test func laterAChangedFirstPageIsGatheredAgain() async throws {
        let counts = Counts()
        let music = client(counts)
        _ = try await visit(music)
        counts.clock += 6 * 60
        counts.firstIds = ["v9", "v1"]
        let again = try await music.revisitedPage(for: liked)
        #expect(again.tracks.first?.id == "v9", "a song liked on the phone leads")
        #expect(counts.continuations == 2, "and the rest is gathered afresh")
        #expect(again.continuation == nil, "whole, so a list on screen never shrinks to regrow")
    }

    @Test func aRefreshGathersEverything() async throws {
        let counts = Counts()
        let music = client(counts)
        _ = try await visit(music)
        counts.clock += 10
        let again = try await music.revisitedPage(for: liked, forceRefresh: true)
        #expect((counts.pages, counts.continuations) == (2, 2), "the whole list is gathered again")
        #expect(again.continuation == nil)
    }

    @Test func aLikeInLiltMakesLikedMusicDue() async throws {
        let counts = Counts()
        let music = client(counts)
        _ = try await visit(music)
        counts.clock += 30
        try await music.setLiked(true, track: Track(id: "v9", title: "Schism", artist: "Tool"))
        _ = try await music.revisitedPage(for: liked)
        #expect(counts.pages == 2, "Liked Music is asked for again after a like")
    }

    @Test func twoAsksAtOnceShareOneRequest() async throws {
        let counts = Counts()
        let music = client(counts, delay: .milliseconds(80))
        async let first = music.page(for: liked)
        async let second = music.page(for: liked)
        let (a, b) = try await (first, second)
        #expect(counts.pages == 1, "one request for both (\(counts.pages))")
        #expect(a.tracks.map(\.id) == b.tracks.map(\.id))
    }
}
