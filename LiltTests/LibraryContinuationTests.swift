import Foundation
import Testing
@testable import Lilt

/// A library shelf longer than one page (25 playlists, albums or artists) comes in pages: the
/// first ends in the older `nextContinuationData` token, as the real feeds' grids and shelves
/// do, and the rest follow it until a page has none. Every page's items are on the shelf, so
/// the 26th saved album shows. A continuation that fails keeps the pages before it and leaves
/// the library stale, to be fetched again next time.
@MainActor
struct LibraryContinuationTests {
    private static func tile(_ id: String, kind pageType: String) -> [String: Any] {
        ["musicTwoRowItemRenderer": [
            "title": ["runs": [["text": id]]],
            "subtitle": ["runs": [["text": "Tool"]]],
            "navigationEndpoint": ["browseEndpoint": [
                "browseId": id,
                "browseEndpointContextSupportedConfigs": ["browseEndpointContextMusicConfig": ["pageType": pageType]],
            ]],
        ]]
    }

    /// The first page: a grid of tiles under the feed's tab, as FEmusic_liked_albums sends it.
    private static func firstPage(_ ids: [String], kind: String, next: String?) -> JSONObject {
        var grid: [String: Any] = ["items": ids.map { tile($0, kind: kind) }]
        if let next { grid["continuations"] = [["nextContinuationData": ["continuation": next]]] }
        return JSONObject(value: ["contents": ["singleColumnBrowseResultsRenderer": ["tabs": [["tabRenderer": ["content": ["sectionListRenderer": [
            "contents": [["gridRenderer": grid]],
            // The tab's own reload token, which isn't a next page.
            "continuations": [["reloadContinuationData": ["continuation": "reload"]]],
        ]]]]]]]])
    }

    /// A later page, in the shape a continuation of a grid comes back in.
    private static func laterPage(_ ids: [String], kind: String, next: String?) -> JSONObject {
        var grid: [String: Any] = ["items": ids.map { tile($0, kind: kind) }]
        if let next { grid["continuations"] = [["nextContinuationData": ["continuation": next]]] }
        return JSONObject(value: ["continuationContents": ["gridContinuation": grid]])
    }

    private static let album = "MUSIC_PAGE_TYPE_ALBUM"

    @Test func everyPageOfAShelfIsOnIt() async throws {
        var asked: [String] = []
        let music = YTMusicClient(auth: AuthService(), fetchPage: { browseId in
            browseId == "FEmusic_liked_albums"
                ? Self.firstPage((1...25).map { "MPREb-\($0)" }, kind: Self.album, next: "t2")
                : JSONObject(value: [:])
        }, fetchContinuation: { token in
            asked.append(token)
            switch token {
            case "t2": return Self.laterPage((26...50).map { "MPREb-\($0)" }, kind: Self.album, next: "t3")
            case "t3": return Self.laterPage(["MPREb-51"], kind: Self.album, next: nil)
            default: throw URLError(.badURL)
            }
        }, persists: false, fetchAccount: { nil })
        let library = try await music.library(forceRefresh: true)
        #expect(library.albums.count == 51, "all three pages (\(library.albums.count))")
        #expect(library.albums.last?.id == "MPREb-51")
        #expect(asked == ["t2", "t3"], "the next pages only, never the tab's reload token")
    }

    @Test func aFailedPageKeepsTheOnesBeforeIt() async throws {
        var fetches = 0
        let music = YTMusicClient(auth: AuthService(), fetchPage: { browseId in
            fetches += 1
            return browseId == "FEmusic_liked_albums"
                ? Self.firstPage((1...25).map { "MPREb-\($0)" }, kind: Self.album, next: "t2")
                : JSONObject(value: [:])
        }, fetchContinuation: { _ in throw URLError(.timedOut) }, persists: false, fetchAccount: { nil })
        let library = try await music.library()
        #expect(library.albums.count == 25, "the first page stays")
        _ = try await music.library()
        #expect(fetches == 8, "a shelf missing pages isn't fresh, so the next ask fetches again")
    }
}
