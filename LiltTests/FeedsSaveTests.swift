import Foundation
import Testing
@testable import Lilt

/// Home, the library and the account are kept on disk so a relaunch starts warm. Opening
/// Library used to write the whole of it there two or three times over, on the main thread:
/// once as the library came in and again for each look at the account, unchanged or not.
@MainActor
struct FeedsSaveTests {
    private static func tile(_ id: String) -> [String: Any] {
        ["musicTwoRowItemRenderer": [
            "title": ["runs": [["text": id]]],
            "navigationEndpoint": ["browseEndpoint": [
                "browseId": id,
                "browseEndpointContextSupportedConfigs": ["browseEndpointContextMusicConfig": ["pageType": "MUSIC_PAGE_TYPE_ALBUM"]],
            ]],
        ]]
    }

    private static func albums(_ ids: [String]) -> JSONObject {
        JSONObject(value: ["contents": ["gridRenderer": ["items": ids.map(tile)]]])
    }

    private static let account = AccountInfo(name: "Matt", email: "m@example.com")

    private static func file() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("feeds-\(UUID().uuidString).json")
    }

    private static func client(at url: URL, albums ids: [String] = ["MPREb-1", "MPREb-2"]) -> YTMusicClient {
        YTMusicClient(auth: AuthService(), fetchPage: { browseId in
            browseId == "FEmusic_liked_albums" ? Self.albums(ids) : JSONObject(value: [:])
        }, fetchContinuation: { _ in JSONObject(value: [:]) }, persists: true, fetchAccount: { Self.account }, persistedURL: url)
    }

    /// Opening Library, as the button's hover and the screen do it: the library, then the
    /// account, asked for again when the screen loads. One write, not one per ask.
    @Test func openingLibraryWritesTheFeedsOnce() async throws {
        let url = Self.file()
        defer { try? FileManager.default.removeItem(at: url) }
        let music = Self.client(at: url)
        _ = try await music.library(forceRefresh: true)
        _ = try await music.account()
        _ = try await music.library()
        _ = try await music.account()
        music.flushToDisk()
        #expect(music.savesToDisk == 1, "the library and an unchanged account were written \(music.savesToDisk) times")
    }

    /// An account that hasn't changed isn't written again.
    @Test func anUnchangedAccountIsNotWrittenAgain() async throws {
        let url = Self.file()
        defer { try? FileManager.default.removeItem(at: url) }
        let music = Self.client(at: url)
        _ = try await music.account()
        music.flushToDisk()
        let first = music.savesToDisk
        for _ in 0..<3 { _ = try await music.account() }
        music.flushToDisk()
        #expect(music.savesToDisk == first, "an unchanged account was written \(music.savesToDisk - first) more times")
    }

    /// A change made just before quitting is on disk once Lilt has flushed, and the next
    /// launch starts from it.
    @Test func aChangeJustBeforeQuittingIsThereOnRelaunch() async throws {
        let url = Self.file()
        defer { try? FileManager.default.removeItem(at: url) }
        let music = Self.client(at: url)
        _ = try await music.library(forceRefresh: true)
        _ = try await music.account()
        music.flushToDisk()
        var saved = BrowsePage(item: BrowseItem(id: "MPREb-new", kind: .album, title: "New", subtitle: "Album"))
        saved.playlistId = "OLAK-new"
        // The next launch, which saves an album and quits straight away.
        let changing = YTMusicClient(auth: AuthService(), write: { _, _ in JSONObject(value: [:]) }, persists: true, fetchAccount: { Self.account }, persistedURL: url)
        try await changing.setSaved(true, page: saved)
        changing.flushToDisk()

        let relaunched = YTMusicClient(auth: AuthService(), persists: true, persistedURL: url)
        #expect(relaunched.cachedLibrary?.albums.map(\.id) == ["MPREb-new", "MPREb-1", "MPREb-2"], "the save just before quitting: \(relaunched.cachedLibrary?.albums.map(\.id) ?? [])")
        #expect(relaunched.cachedAccount == Self.account)
    }
}
