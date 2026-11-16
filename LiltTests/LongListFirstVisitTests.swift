import AppKit
import SwiftUI
import Testing
@testable import Lilt

/// Liked Music opened for the first time since launch (nothing of it kept) stayed an empty
/// skeleton, live, while its ten pages came in; it showed only when opened a second time. Its
/// first hundred songs should be there to play as soon as the first page arrives, the rest
/// joining them below. The page here is ten pages of a hundred, as Liked Music is.
@MainActor
struct LongListFirstVisitTests {
    private static let size = CGSize(width: 320, height: 800)

    private static func row(_ id: String) -> [String: Any] {
        ["musicResponsiveListItemRenderer": [
            "playlistItemData": ["videoId": id, "playlistSetVideoId": "set-\(id)"],
            "flexColumns": [
                ["musicResponsiveListItemFlexColumnRenderer": ["text": ["runs": [["text": "Song \(id)"]]]]],
                ["musicResponsiveListItemFlexColumnRenderer": ["text": ["runs": [["text": "Tool"]]]]],
            ],
            "fixedColumns": [["musicResponsiveListItemFixedColumnRenderer": ["text": ["runs": [["text": "3:45"]]]]]],
        ]]
    }

    private static func more(_ token: String) -> [String: Any] {
        ["continuationItemRenderer": ["continuationEndpoint": ["continuationCommand": ["token": token, "request": "CONTINUATION_REQUEST_TYPE_BROWSE"]]]]
    }

    private static func rows(_ page: Int) -> [[String: Any]] { (1...100).map { row("p\(page)-\($0)") } }

    private static var firstPage: JSONObject {
        JSONObject(value: ["contents": ["twoColumnBrowseResultsRenderer": ["secondaryContents": ["sectionListRenderer": ["contents": [[
            "musicPlaylistShelfRenderer": ["playlistId": "LM", "contents": rows(1) + [more("t2")]],
        ]]]]]]])
    }

    private static func later(_ page: Int) -> JSONObject {
        JSONObject(value: ["onResponseReceivedActions": [["appendContinuationItemsAction": ["continuationItems": rows(page) + (page < 10 ? [more("t\(page + 1)")] : [])]]]])
    }

    @Test func theFirstPageCanBePlayedWhileTheRestComesIn() async throws {
        let liked = BrowseItem(id: "VLLM-first-visit", kind: .playlist, title: "Liked Music", subtitle: "Auto playlist")
        try await withFakePlayer([Track(id: "x", title: "x", artist: "x")], gapless: false) { player, _ in
            let auth = AuthService()
            let music = YTMusicClient(auth: auth, fetchPage: { _ in
                try await Task.sleep(for: .milliseconds(300))
                return Self.firstPage
            }, fetchContinuation: { token in
                try await Task.sleep(for: .milliseconds(150))
                return Self.later(Int(token.dropFirst())!)
            }, persists: false, fetchAccount: { nil })
            let navigation = NavigationModel()
            let saved = UserDefaults.standard.data(forKey: "navigationState")
            defer { if let saved { UserDefaults.standard.set(saved, forKey: "navigationState") } else { UserDefaults.standard.removeObject(forKey: "navigationState") } }
            navigation.path = [liked]
            let view = BrowseScreen(item: liked)
                .frame(width: Self.size.width, height: Self.size.height)
                .environment(auth)
                .environment(player)
                .environment(music)
                .environment(navigation)
                .environment(ScrollTracker())
                .environment(CollapsedSections())
            let hosting = NSHostingView(rootView: AnyView(view))
            hosting.frame = CGRect(origin: .zero, size: Self.size)
            let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -10_000, y: -10_000), size: Self.size), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = hosting
            window.orderFront(nil)
            defer { window.close() }

            // The first page lands at 0.3s; by 1.5s its songs are long since playable.
            try await Task.sleep(for: .milliseconds(1500))
            var played = false
            for y in stride(from: 360.0, through: 780, by: 20) where !played {
                let location = CGPoint(x: Self.size.width / 2, y: Self.size.height - y)
                let time = ProcessInfo.processInfo.systemUptime
                for (type, offset) in [(NSEvent.EventType.leftMouseDown, 0.0), (.leftMouseUp, 0.05)] {
                    window.sendEvent(NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: time + offset, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)!)
                }
                try await Task.sleep(for: .milliseconds(40))
                played = player.current?.id.hasPrefix("p1-") == true
            }
            #expect(played, "a song from the first page plays when clicked, 1.5s after the page opened (playing \(player.current?.id ?? "nil"))")
        }
    }
}
