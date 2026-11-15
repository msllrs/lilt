import Foundation
import Testing
@testable import Lilt

/// A playlist longer than one page: YouTube Music sends its first hundred songs and a token for
/// the next, as it does for Liked Music and an artist's songs. Stood in for here with a playlist
/// of five songs over three pages of two, two and one.
@MainActor
struct PlaylistContinuationTests {
    private static func row(_ id: String) -> [String: Any] {
        ["musicResponsiveListItemRenderer": [
            "playlistItemData": ["videoId": id],
            "flexColumns": [["musicResponsiveListItemFlexColumnRenderer": ["text": ["runs": [["text": "Song \(id)"]]]]]],
        ]]
    }

    /// The end of a page that has more after it.
    private static func more(_ token: String) -> [String: Any] {
        ["continuationItemRenderer": ["continuationEndpoint": ["continuationCommand": ["token": token, "request": "CONTINUATION_REQUEST_TYPE_BROWSE"]]]]
    }

    private static let firstPage: [String: Any] = [
        "contents": ["twoColumnBrowseResultsRenderer": ["secondaryContents": ["sectionListRenderer": ["contents": [[
            "musicPlaylistShelfRenderer": ["playlistId": "PLlong", "contents": [row("v1"), row("v2"), more("page2")]],
        ]]]]]],
    ]

    private static func continuation(_ items: [[String: Any]]) -> [String: Any] {
        ["onResponseReceivedActions": [["appendContinuationItemsAction": ["continuationItems": items]]]]
    }

    private static let pages: [String: [String: Any]] = [
        "page2": continuation([row("v3"), row("v4"), more("page3")]),
        "page3": continuation([row("v5")]),
    ]

    private let playlist = BrowseItem(id: "VLPLlong", kind: .playlist, title: "Long", subtitle: "Matt")

    private func client(asked: @escaping (String) -> Void = { _ in }) -> YTMusicClient {
        YTMusicClient(
            auth: AuthService(),
            fetchPage: { _ in JSONObject(value: Self.firstPage) },
            fetchContinuation: { token in
                asked(token)
                guard let page = Self.pages[token] else { throw URLError(.badServerResponse) }
                return JSONObject(value: page)
            },
            persists: false
        )
    }

    @Test func theFirstPageArrivesWithWhereTheRestIs() async throws {
        let page = try await client().page(for: playlist)
        #expect(page.tracks.map(\.id) == ["v1", "v2"], "the page draws its first songs without waiting for the rest")
        #expect(page.continuation == "page2")
    }

    @Test func eachNextPageAddsItsSongsInOrder() async throws {
        let music = client()
        var page = try await music.page(for: playlist)
        page = try await music.nextPage(of: page)
        #expect(page.tracks.map(\.id) == ["v1", "v2", "v3", "v4"])
        #expect(page.continuation == "page3")
        page = try await music.nextPage(of: page)
        #expect(page.tracks.map(\.id) == ["v1", "v2", "v3", "v4", "v5"])
        #expect(page.continuation == nil, "the last page has no more after it")
        #expect(music.cachedPage(for: playlist)?.tracks.count == 5, "going back draws the whole list")
    }

    /// What Play and Shuffle Play on a playlist's row take, from search or the library: every song.
    @Test func theWholePlaylistIsEverySong() async throws {
        var asked: [String] = []
        let page = try await client { asked.append($0) }.fullPage(for: playlist)
        #expect(page.tracks.map(\.id) == ["v1", "v2", "v3", "v4", "v5"])
        #expect(asked == ["page2", "page3"], "each page asked for once, in order")
    }

    @Test func theTokenIsFoundInEitherShape() {
        #expect(SearchParser.continuationToken(in: Self.firstPage) == "page2")
        // The older shape some shelves still send.
        let older: [String: Any] = ["contents": ["musicPlaylistShelfRenderer": [
            "contents": [Self.row("v1")],
            "continuations": [["nextContinuationData": ["continuation": "older2"]]],
        ]]]
        #expect(SearchParser.continuationToken(in: older) == "older2")
        #expect(SearchParser.continuationToken(in: Self.pages["page3"]!) == nil)
    }
}
