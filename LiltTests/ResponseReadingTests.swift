import Foundation
import Testing
@testable import Lilt

/// Every response YouTube Music sends back is turned from bytes into JSON, and from JSON into
/// songs and pages, away from the main thread: Liked Music's pages are over a megabyte each, a
/// search is two responses, a library open four feeds of pages, and read on the main thread
/// each one held a scroll or the search field for as long as it took.
@MainActor
struct ResponseReadingTests {
    /// A renderer padded the way real ones are, with menus, overlays and thumbnails nested two
    /// dozen deep, which a walk for renderers goes all the way through.
    private static func padding(_ i: Int) -> Any {
        var deep: Any = ["text": "padding \(i)"]
        for level in 0..<24 { deep = ["level\(level)": deep, "sibling\(level)": ["a": [1, 2, 3], "b": "x"]] }
        return deep
    }

    private static func songRow(_ i: Int) -> [String: Any] {
        ["musicResponsiveListItemRenderer": [
            "playlistItemData": ["videoId": "v\(i)"],
            "flexColumns": [["musicResponsiveListItemFlexColumnRenderer": ["text": ["runs": [["text": "Song \(i)"]]]]]],
            "menu": padding(i), "overlay": padding(i), "thumbnail": padding(i),
        ]]
    }

    private static func tile(_ i: Int, kind: String) -> [String: Any] {
        ["musicTwoRowItemRenderer": [
            "title": ["runs": [["text": "Tile \(i)"]]],
            "navigationEndpoint": ["browseEndpoint": [
                "browseId": "MPREb-\(i)",
                "browseEndpointContextSupportedConfigs": ["browseEndpointContextMusicConfig": ["pageType": kind]],
            ]],
            "menu": padding(i), "thumbnailRenderer": padding(i),
        ]]
    }

    /// The longest the main actor went without a turn while `work` ran, and how long it took.
    /// The clock starts before the ticker's first turn, so work that holds the main thread
    /// from the moment it is called counts too.
    private static func longestMainGap(during work: () async throws -> Void) async rethrows -> (gap: Duration, took: Duration) {
        var longest: Duration = .zero
        var ticking = true
        let clock = ContinuousClock()
        var last = clock.now
        let ticker = Task { @MainActor in
            while ticking {
                try? await Task.sleep(for: .milliseconds(2))
                let now = clock.now
                longest = max(longest, now - last)
                last = now
            }
        }
        let started = clock.now
        try await work()
        let took = clock.now - started
        longest = max(longest, clock.now - last)
        ticking = false
        await ticker.value
        return (longest, took)
    }

    /// A search's two responses, its songs and everything else, are read off the main thread.
    @Test func aBigSearchIsReadOffTheMainThread() async throws {
        let response = JSONObject(value: ["contents": ["tabbedSearchResultsRenderer": ["tabs": (0..<600).map(Self.songRow)]]])
        let music = YTMusicClient(auth: AuthService(), persists: false, fetchAccount: { nil }, fetchSearch: { _, _ in response })
        var results = SearchResults()
        let (gap, took) = try await Self.longestMainGap { results = try await music.search("big") }
        #expect(results.songs.count == 600, "the search was read (\(results.songs.count) songs)")
        #expect(gap < .milliseconds(50), "reading the search took \(took) and held the main thread for \(gap) at a stretch")
    }

    /// Home's shelves, the active channel's and each other one's, are read off the main thread.
    @Test func aBigHomeIsReadOffTheMainThread() async throws {
        let shelves: [[String: Any]] = (0..<24).map { shelf in
            ["musicCarouselShelfRenderer": [
                "header": ["musicCarouselShelfBasicHeaderRenderer": ["title": ["runs": [["text": "Shelf \(shelf)"]]]]],
                "contents": (0..<40).map { Self.tile(shelf * 100 + $0, kind: "MUSIC_PAGE_TYPE_ALBUM") },
            ]]
        }
        let response = JSONObject(value: ["contents": ["sectionListRenderer": ["contents": shelves]]])
        let account = AccountInfo(name: "Matt", email: "m@example.com", alternatives: [.init(name: "Lilt Radio", pageId: "p1")])
        let music = YTMusicClient(auth: AuthService(), persists: false, fetchAccount: { account }, fetchHome: { _ in response })
        var sections: [HomeSection] = []
        let (gap, took) = try await Self.longestMainGap { sections = try await music.home(forceRefresh: true) }
        #expect(sections.count == 48, "both channels' shelves were read (\(sections.count))")
        #expect(gap < .milliseconds(50), "reading the home took \(took) and held the main thread for \(gap) at a stretch")
    }

    /// The library's feeds, every page of each, are read off the main thread.
    @Test func aBigLibraryIsReadOffTheMainThread() async throws {
        func page(_ feed: String, _ number: Int, next: String?) -> JSONObject {
            var grid: [String: Any] = ["items": (0..<100).map { Self.tile(number * 1000 + $0, kind: "MUSIC_PAGE_TYPE_ALBUM") }]
            if let next { grid["continuations"] = [["nextContinuationData": ["continuation": next]]] }
            return JSONObject(value: ["continuationContents": ["gridContinuation": grid], "feed": feed])
        }
        let music = YTMusicClient(auth: AuthService(), fetchPage: { browseId in
            browseId == "FEmusic_liked_albums" ? page(browseId, 0, next: "t1") : JSONObject(value: [:])
        }, fetchContinuation: { token in
            let number = Int(token.dropFirst())!
            return page("FEmusic_liked_albums", number, next: number < 7 ? "t\(number + 1)" : nil)
        }, persists: false, fetchAccount: { nil })
        var library = LibraryContent()
        let (gap, took) = try await Self.longestMainGap { library = try await music.library(forceRefresh: true) }
        #expect(library.albums.count == 800, "every page was read (\(library.albums.count) albums)")
        #expect(gap < .milliseconds(50), "reading the library took \(took) and held the main thread for \(gap) at a stretch")
    }

    /// A response's bytes, the size of ten of Liked Music's pages, become JSON off the main
    /// thread.
    @Test func aBigResponseIsDecodedOffTheMainThread() async throws {
        let data = try JSONSerialization.data(withJSONObject: ["contents": (0..<4_000).map(Self.songRow)])
        var decoded: JSONObject?
        let (gap, took) = try await Self.longestMainGap { decoded = try await InnerTubeClient.decode(data) }
        #expect(decoded?.value["contents"] != nil, "the response was decoded")
        #expect(gap < .milliseconds(50), "decoding \(data.count / 1_000_000) MB took \(took) and held the main thread for \(gap) at a stretch")
    }
}
