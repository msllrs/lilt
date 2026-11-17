import AppKit
import SwiftUI
import Testing
@testable import Lilt

/// A change rebuilds only the song rows it touches. Pausing redraws the playing row alone;
/// queueing a song, a like made elsewhere and the pointer leaving the panel redraw none; and a
/// home shelf goes through each of its songs once, where every song went through the whole
/// shelf to find itself. Every row rebuilt for nothing is work on the main thread, felt as a
/// hitch in whatever else is moving.
@MainActor
struct RowInvalidationTests {
    private static let width: CGFloat = 320

    private static func songs(_ prefix: String, count: Int = 20) -> [Track] {
        (0..<count).map { Track(id: "\(prefix)-\($0)", title: "Song \($0)", artist: "Tool", durationText: "3:\(10 + $0)") }
    }

    private struct Hosted {
        let window: NSWindow
        let hosting: NSHostingView<AnyView>
    }

    private func host(_ view: some View, player: PlayerService, music: YTMusicClient, rest: PanelRest? = nil, height: CGFloat = 1400) -> Hosted {
        let root = AnyView(view
            .environment(player)
            .environment(music)
            .environment(NavigationModel())
            .environment(ScrollTracker())
            .environment(CollapsedSections())
            .environment(rest)
            .frame(width: Self.width, height: height, alignment: .top))
        let hosting = NSHostingView(rootView: root)
        hosting.frame = CGRect(x: 0, y: 0, width: Self.width, height: height)
        let window = NSWindow(contentRect: CGRect(x: -10_000, y: -10_000, width: Self.width, height: height), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderFrontRegardless()
        return Hosted(window: window, hosting: hosting)
    }

    private func settle(_ hosted: Hosted) async {
        for _ in 0..<10 {
            try? await Task.sleep(for: .milliseconds(20))
            hosted.hosting.layoutSubtreeIfNeeded()
        }
    }

    private func rowsBuilt(_ songs: [Track]) -> Int { songs.reduce(0) { $0 + (RowBuildCounts.rows[$1.id] ?? 0) } }
    private func slotsBuilt(_ songs: [Track]) -> Int { songs.reduce(0) { $0 + (RowBuildCounts.slots[$1.id] ?? 0) } }
    private func forget(_ songs: [Track]) {
        for song in songs {
            RowBuildCounts.rows[song.id] = nil
            RowBuildCounts.slots[song.id] = nil
        }
    }

    /// A list of `songs` playing its first, hosted, with every row built and the count started
    /// over; `change` is then made and the rows it rebuilt are returned.
    private func rowsRebuilt(
        by change: (PlayerService, FakePlayers, YTMusicClient, PanelRest) -> Void,
        _ songs: [Track]
    ) async throws -> Int {
        var rebuilt = 0
        try await withFakePlayer(songs, gapless: false) { player, fakes in
            let music = YTMusicClient(auth: AuthService(), persists: false)
            let rest = PanelRest(schedule: { _, _ in {} }, isButtonDown: { false })
            let hosted = host(VStack(spacing: 0) { TrackRows(tracks: songs) }, player: player, music: music, rest: rest)
            defer { hosted.window.close() }
            fakes.startPlaying(player)
            await settle(hosted)
            #expect(rowsBuilt(songs) >= songs.count, "every row was built to start with")
            forget(songs)
            change(player, fakes, music, rest)
            await settle(hosted)
            rebuilt = rowsBuilt(songs)
            forget(songs)
        }
        return rebuilt
    }

    @Test func pausingRebuildsOnlyThePlayingRow() async throws {
        let songs = Self.songs("pause")
        let rebuilt = try await rowsRebuilt(by: { player, _, _, _ in
            #expect(player.isPlaying)
            player.togglePlayPause()
            #expect(!player.isPlaying)
        }, songs)
        #expect(rebuilt <= 2, "the playing row redraws its pause; the other 19 needn't (\(rebuilt) rebuilt)")
    }

    @Test func queueingASongRebuildsNoRows() async throws {
        let songs = Self.songs("queue")
        let rebuilt = try await rowsRebuilt(by: { player, _, _, _ in
            _ = player.enqueue(Track(id: "queue-extra", title: "Extra", artist: "Tool"))
        }, songs)
        #expect(rebuilt <= 1, "the playing song is the same and so is every row (\(rebuilt) rebuilt)")
    }

    @Test func aLikeElsewhereRebuildsNoRows() async throws {
        let songs = Self.songs("like")
        let rebuilt = try await rowsRebuilt(by: { _, _, music, _ in
            music.noteLiked(true, track: Track(id: "like-elsewhere", title: "Elsewhere", artist: "Tool"))
        }, songs)
        #expect(rebuilt <= 1, "only a menu shows likes, and none is open (\(rebuilt) rebuilt)")
    }

    /// The menu reads the likes in a body of its own, and still follows them: a like made
    /// elsewhere offers Remove from Liked Music the next time the row is right-clicked.
    @Test func theMenuStillFollowsALikeMadeElsewhere() async throws {
        let song = Track(id: "menu-like", title: "Schism", artist: "Tool", durationText: "6:47", isLiked: false)
        try await withFakePlayer([], gapless: false) { player, _ in
            let music = YTMusicClient(auth: AuthService(), persists: false)
            let hosted = host(TrackRow(track: song, isCurrent: false, isPlaying: false) {}, player: player, music: music, height: 56)
            defer { hosted.window.close() }
            await settle(hosted)
            @MainActor func titles() -> [String] {
                let point = NSPoint(x: Self.width / 2, y: 28)
                let event = NSEvent.mouseEvent(
                    with: .rightMouseDown, location: point, modifierFlags: [], timestamp: 0,
                    windowNumber: hosted.window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
                )!
                guard let menu = (hosted.hosting.hitTest(point) ?? hosted.hosting).menu(for: event) else { return [] }
                menu.delegate?.menuNeedsUpdate?(menu)
                return menu.items.map(\.title)
            }
            #expect(titles().contains("Like"))
            music.noteLiked(true, track: song)
            await settle(hosted)
            let liked = titles()
            #expect(liked.contains("Remove from Liked Music") && !liked.contains("Like"), "the menu shows the like (\(liked))")
        }
    }

    @Test func thePointerLeavingRebuildsNoRows() async throws {
        let songs = Self.songs("pointer")
        let rebuilt = try await rowsRebuilt(by: { _, _, _, rest in
            rest.pointerExited()
            #expect(!rest.isPointerInside)
        }, songs)
        #expect(rebuilt <= 1, "only the lengths fade (\(rebuilt) rebuilt)")
    }

    /// A feed of one shelf of `count` songs, as the home endpoint returns it.
    private static func feed(_ title: String, _ songs: [Track]) -> JSONObject {
        JSONObject(value: ["contents": ["musicCarouselShelfRenderer": [
            "header": ["musicCarouselShelfBasicHeaderRenderer": ["title": ["runs": [["text": title]]]]],
            "contents": songs.map { song in ["musicTwoRowItemRenderer": [
                "title": ["runs": [["text": song.title]]],
                "navigationEndpoint": ["watchEndpoint": ["videoId": song.id]],
            ]] },
        ]]])
    }

    @Test func aHomeShelfGoesThroughEachSongOnce() async throws {
        let songs = Self.songs("shelf")
        forget(songs)
        try await withFakePlayer([], gapless: false) { player, _ in
            let music = YTMusicClient(
                auth: AuthService(), persists: false,
                fetchAccount: { nil },
                fetchHome: { _ in Self.feed("Row count shelf", songs) }
            )
            let hosted = host(HomeScreen(scroll: .constant(ListScroll())), player: player, music: music, height: 2000)
            defer { hosted.window.close() }
            for _ in 0..<5 { await settle(hosted) }
            let rows = rowsBuilt(songs)
            let slots = slotsBuilt(songs)
            forget(songs)
            #expect(rows >= songs.count, "the shelf's songs are on screen (\(rows) rows built)")
            #expect(slots <= songs.count * 3, "each song's place is looked at once or so, not once per song in the shelf (\(slots) for \(songs.count) songs)")
        }
    }
}
