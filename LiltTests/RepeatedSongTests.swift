import AppKit
import SwiftUI
import Testing
@testable import Lilt

/// A playlist can hold the same song more than once (several of the real library's do), and
/// each time is a row of its own: YouTube Music gives every entry its own id
/// (`playlistSetVideoId`), so the copy can be seen, played from and removed. A response that
/// repeats a row with the same entry id, as a continuation can, still shows it once.
@MainActor
struct RepeatedSongTests {
    private static func row(_ videoId: String, entry: String?, title: String) -> [String: Any] {
        var data: [String: Any] = ["videoId": videoId]
        if let entry { data["playlistSetVideoId"] = entry }
        return ["musicResponsiveListItemRenderer": [
            "playlistItemData": data,
            "flexColumns": [["musicResponsiveListItemFlexColumnRenderer": ["text": ["runs": [["text": title]]]]]],
        ]]
    }

    private let playlist = BrowseItem(id: "VLPL-mix", kind: .playlist, title: "Mix", subtitle: "Matt")

    @Test func eachEntryOfARepeatedSongIsARow() {
        let response: [String: Any] = ["contents": ["musicPlaylistShelfRenderer": ["contents": [
            Self.row("schism", entry: "E1", title: "Schism"),
            Self.row("parabola", entry: "E2", title: "Parabola"),
            Self.row("schism", entry: "E3", title: "Schism"),
        ]]]]
        let page = SearchParser.browsePage(from: response, for: playlist)
        #expect(page.tracks.map(\.id) == ["schism", "parabola", "schism"])
        #expect(page.tracks.map(\.entryId) == ["E1", "E2", "E3"])
    }

    @Test func theSameEntryTwiceIsOneRow() {
        var page = BrowsePage(item: playlist)
        let first: [String: Any] = ["contents": [Self.row("schism", entry: "E1", title: "Schism")]]
        SearchParser.appendTracks(in: first, to: &page)
        SearchParser.appendTracks(in: first, to: &page)
        #expect(page.tracks.count == 1)
    }

    /// Rows without entry ids (an album's) are still told apart by song.
    @Test func rowsWithoutEntryIdsAreOncePerSong() {
        var page = BrowsePage(item: playlist)
        SearchParser.appendTracks(in: ["contents": [Self.row("schism", entry: nil, title: "Schism"), Self.row("schism", entry: nil, title: "Schism")]], to: &page)
        #expect(page.tracks.count == 1)
    }

    /// Both rows draw, and a click on the second plays the list from there.
    @Test func bothRowsShowAndTheSecondPlaysFromItsPlace() async throws {
        var first = Track(id: "schism", title: "Schism", artist: "Tool")
        first.entryId = "E1"
        var second = first
        second.entryId = "E3"
        let list = [first, Track(id: "parabola", title: "Parabola", artist: "Tool"), second]
        try await withFakePlayer([Track(id: "x", title: "x", artist: "x")], gapless: false) { player, _ in
            let auth = AuthService()
            let view = VStack(spacing: 0) { TrackRows(tracks: list) }
                .environment(auth)
                .environment(player)
                .environment(YTMusicClient(auth: auth, persists: false))
                .environment(NavigationModel())
                .frame(width: 320)
            let hosting = NSHostingView(rootView: view)
            let window = NSWindow(contentRect: CGRect(x: -10_000, y: -10_000, width: 320, height: 400), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = hosting
            window.orderFrontRegardless()
            defer { window.close() }
            for _ in 0..<10 { try? await Task.sleep(for: .milliseconds(20)) }
            let rowHeight = Theme.Size.rowArtwork + Theme.Space.rowPadding * 2
            #expect(hosting.fittingSize.height >= rowHeight * 3 - 1, "three rows (\(hosting.fittingSize.height) for rows of \(rowHeight))")

            hosting.frame = CGRect(origin: .zero, size: hosting.fittingSize)
            window.setContentSize(hosting.fittingSize)
            hosting.layoutSubtreeIfNeeded()
            let y = window.frame.height - (rowHeight * 2.5)
            let time = ProcessInfo.processInfo.systemUptime
            for (type, offset) in [(NSEvent.EventType.leftMouseDown, 0.0), (.leftMouseUp, 0.05)] {
                window.sendEvent(NSEvent.mouseEvent(with: type, location: CGPoint(x: 160, y: y), modifierFlags: [], timestamp: time + offset, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)!)
            }
            for _ in 0..<10 where player.currentIndex != 2 { try? await Task.sleep(for: .milliseconds(20)) }
            #expect(player.current?.id == "schism")
            #expect(player.currentIndex == 2, "the second copy plays, at its own place in the list")
        }
    }
}
