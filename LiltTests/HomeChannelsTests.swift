import Foundation
import Testing
@testable import Lilt

/// Home shows the active channel's feed and then each other channel's on the login, labelled
/// with its name. The other feeds are asked for as soon as the account says which channels
/// there are, alongside the active one and each other, rather than one after another once it
/// has arrived; the shelves still come in that order.
@MainActor
struct HomeChannelsTests {
    private static func feed(_ title: String) -> JSONObject {
        JSONObject(value: ["contents": ["musicCarouselShelfRenderer": [
            "header": ["musicCarouselShelfBasicHeaderRenderer": ["title": ["runs": [["text": title]]]]],
            "contents": [["musicTwoRowItemRenderer": [
                "title": ["runs": [["text": "\(title) song"]]],
                "navigationEndpoint": ["watchEndpoint": ["videoId": "v-\(title)"]],
            ]]],
        ]]])
    }

    @Test func otherChannelsAreFetchedAlongsideTheActiveOne() async throws {
        var inFlight = 0
        var mostAtOnce = 0
        let account = AccountInfo(name: "Matt", email: "m@example.com", alternatives: [
            .init(name: "Lilt Radio", pageId: "p1"),
            .init(name: "Night Shift", pageId: "p2"),
        ])
        let music = YTMusicClient(
            auth: AuthService(), persists: false,
            fetchAccount: { account },
            fetchHome: { pageId in
                inFlight += 1
                mostAtOnce = max(mostAtOnce, inFlight)
                defer { inFlight -= 1 }
                // The active feed is the slowest, as it is for real (about 870ms against 600).
                try await Task.sleep(for: .milliseconds(pageId == nil ? 300 : 150))
                switch pageId {
                case .none: return Self.feed("Quick picks")
                case .some("p1"): return Self.feed("Mixed for you")
                default: return Self.feed("Long listens")
                }
            }
        )
        let started = ContinuousClock.now
        let sections = try await music.home(forceRefresh: true)
        let took = ContinuousClock.now - started
        #expect(mostAtOnce == 3, "all three feeds were on their way at once")
        #expect(took < .milliseconds(420), "the home took as long as its slowest feed, not their sum (\(took))")
        #expect(sections.map(\.title) == ["Quick picks", "Mixed for you · Lilt Radio", "Long listens · Night Shift"])
    }

    @Test func aChannelThatFailsIsLeftOut() async throws {
        let account = AccountInfo(name: "Matt", email: "m@example.com", alternatives: [.init(name: "Lilt Radio", pageId: "p1"), .init(name: "Night Shift", pageId: "p2")])
        let music = YTMusicClient(
            auth: AuthService(), persists: false,
            fetchAccount: { account },
            fetchHome: { pageId in
                if pageId == .some("p1") { throw URLError(.timedOut) }
                return Self.feed(pageId == nil ? "Quick picks" : "Long listens")
            }
        )
        let sections = try await music.home(forceRefresh: true)
        #expect(sections.map(\.title) == ["Quick picks", "Long listens · Night Shift"])
    }

    /// A channel with no page id is the login's primary account, asked for by name rather
    /// than left to whichever account is selected.
    @Test func thePrimaryAccountIsAskedForAsSuch() async throws {
        var asked: [String??] = []
        let account = AccountInfo(name: "Lilt Radio", email: "m@example.com", alternatives: [.init(name: "Matt", pageId: nil)])
        let music = YTMusicClient(auth: AuthService(), persists: false, fetchAccount: { account }, fetchHome: { pageId in
            asked.append(pageId)
            return Self.feed("Quick picks")
        })
        _ = try await music.home(forceRefresh: true)
        #expect(asked.contains { $0 == .some(nil) }, "the primary account's feed is asked for as .some(nil): \(asked)")
    }
}
