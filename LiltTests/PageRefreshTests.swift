import Foundation
import Testing
@testable import Lilt

/// A playlist changed elsewhere (a song liked on the phone) has to show up the next time its page
/// opens in Lilt. The cached copy is only there to draw the first frame.
@MainActor
struct PageRefreshTests {
    /// A browse response whose header carries `title`.
    private static func response(title: String) -> JSONObject {
        JSONObject(value: ["header": ["musicResponsiveHeaderRenderer": ["title": ["runs": [["text": title]]]]]])
    }

    @Test func reopeningAPageFetchesItAgain() async throws {
        var served = "Before"
        var fetches = 0
        let music = YTMusicClient(auth: AuthService(), fetchPage: { _ in
            fetches += 1
            return Self.response(title: served)
        })
        let item = BrowseItem(id: "VLLM", kind: .playlist, title: "Liked Music", subtitle: "", artworkURL: nil)

        #expect(try await music.page(for: item).item.title == "Before")
        served = "After"
        #expect(try await music.page(for: item).item.title == "After", "a second open shows what the server has now")
        #expect(fetches == 2)
        #expect(music.cachedPage(for: item)?.item.title == "After", "the cache keeps the latest copy for the next first frame")
    }
}
