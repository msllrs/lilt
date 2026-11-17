import Testing
@testable import Lilt

/// The drawer's feed list: each entry is a mount of its own, on the host that serves mounts
/// directly, and already in the form the field and `StreamAddress` take.
struct StreamFeedTests {
    @Test func everyFeedHasItsOwnMount() {
        let mounts = StreamFeed.allCases.map(\.mount)
        #expect(Set(mounts).count == mounts.count)
    }

    @Test func everyFeedHasItsOwnName() {
        let names = StreamFeed.allCases.map(\.name)
        #expect(Set(names).count == names.count)
        #expect(names.allSatisfy { !$0.isEmpty })
    }

    @Test func everyFeedIsAlreadyTheStreamAddress() {
        for feed in StreamFeed.allCases {
            #expect(feed.url.hasPrefix("https://d.liveatc.net/"))
            #expect(StreamAddress.stream(from: feed.url)?.absoluteString == feed.url)
        }
    }

    @Test func tokyoIsFirst() {
        #expect(StreamFeed.allCases.first == .tokyoHaneda)
    }
}
