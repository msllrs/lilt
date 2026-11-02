import Foundation
import Testing
@testable import Lilt

/// What a notice's Undo takes back: queue changes exactly, likes the way they were set, and a
/// playlist add by the entry YouTube made. Every YouTube write here goes to a fake.
@MainActor
struct NoticeUndoTests {
    private let schism = Track(id: "tuw1ziytBDk", title: "Schism", artist: "Tool")
    private let parabola = Track(id: "VtNxCk5Ag7w", title: "Parabola", artist: "Tool")
    private let lateralus = Track(id: "Y7JG63IuaWs", title: "Lateralus", artist: "Tool")
    private let sober = Track(id: "nspxAG12Cpc", title: "Sober", artist: "Tool")
    private let forty = Track(id: "ZLDUbN0Gp2M", title: "Forty Six & 2", artist: "Tool")

    /// A player resumed on `queue[0]` with `manual` of the rest queued by hand, loading nothing
    /// into a web player. The app's saved playback is put back afterwards.
    private func withPlayer(_ queue: [Track], manual: Int = 0, _ body: (PlayerService) throws -> Void) throws {
        let key = "playbackState"
        let saved = UserDefaults.standard.data(forKey: key)
        defer { if let saved { UserDefaults.standard.set(saved, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) } }
        let state: [String: Any] = ["queue": try JSONSerialization.jsonObject(with: JSONEncoder().encode(queue)), "index": 0, "time": 0, "manualCount": manual]
        UserDefaults.standard.set(try JSONSerialization.data(withJSONObject: state), forKey: key)
        try body(PlayerService(auth: AuthService(), makeBridge: { FakeBridge() }))
    }

    private func notices() -> NoticeCenter { NoticeCenter(clock: ManualNoticeClock()) }

    @Test func undoingARemovalPutsTheSongBackWhereItWas() throws {
        try withPlayer([forty, schism, parabola, lateralus, sober], manual: 3) { player in
            let center = notices()
            let entry = player.upcomingEntries[1]
            RowMenu.removeFromQueue(entry.id, player: player, notices: center)
            #expect(player.upcoming.map(\.title) == ["Schism", "Lateralus"])
            #expect(center.current?.spoken == "Removed Parabola")
            #expect(center.performAction(key: "z"))
            #expect(player.upcoming.map(\.title) == ["Schism", "Parabola", "Lateralus"])
            #expect(player.automaticUpcoming.map(\.title) == ["Sober"], "the rest of the list is untouched")
        }
    }

    @Test func undoingPlayNextTakesOutThatEntryEvenWithACopyQueued() throws {
        try withPlayer([forty, schism, sober], manual: 1) { player in
            let center = notices()
            let earlier = try #require(player.upcomingEntries.first)
            RowMenu.playNext(schism, player: player, notices: center)
            #expect(player.upcoming.map(\.title) == ["Schism", "Schism"])
            #expect(center.current?.spoken == "Next Schism")
            center.performAction(key: "z")
            #expect(player.upcomingEntries.map(\.id) == [earlier.id], "the copy queued before stays")
            #expect(player.automaticUpcoming.map(\.title) == ["Sober"])
        }
    }

    @Test func undoingPlayNextAfterTheQueueMovedStillFindsIt() throws {
        try withPlayer([forty, sober]) { player in
            let center = notices()
            RowMenu.playNext([schism, parabola], named: "Lateralus", artwork: nil, player: player, notices: center)
            player.enqueue(lateralus)
            player.moveUpcoming(from: [0], to: 3)
            #expect(player.upcoming.map(\.title) == ["Parabola", "Lateralus", "Schism"])
            center.performAction()
            #expect(player.upcoming.map(\.title) == ["Lateralus"])
        }
    }

    @Test func undoingAddToQueueTakesOutThatEntry() throws {
        try withPlayer([forty, schism, sober], manual: 1) { player in
            let center = notices()
            RowMenu.enqueue(schism, player: player, notices: center)
            #expect(player.upcoming.map(\.title) == ["Schism", "Schism"])
            #expect(center.current?.spoken == "Queued Schism")
            let earlier = player.upcomingEntries[0].id
            center.performAction()
            #expect(player.upcomingEntries.map(\.id) == [earlier])
        }
    }

    @Test func likeUndoesBackToUnliked() async throws {
        var calls: [String] = []
        let music = YTMusicClient(auth: AuthService(), write: { endpoint, _ in
            calls.append(endpoint)
            return JSONObject(value: [:])
        })
        try withPlayer([forty]) { player in
            let center = notices()
            RowMenu.setLiked(true, schism, player: player, music: music, notices: center)
            #expect(center.current?.spoken == "Liked \(schism.title)", "a notice names the song it acted on")
            center.performAction()
        }
        for _ in 0..<50 where calls.count < 2 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(calls == ["like/like", "like/removelike"])
        #expect(music.isLiked(schism) == false)
    }

    /// edit_playlist's answer to an add, as YouTube Music sends it.
    private let addedResponse: [String: Any] = [
        "status": "STATUS_SUCCEEDED",
        "playlistEditResults": [["playlistEditVideoAddedResultData": ["videoId": "tuw1ziytBDk", "setVideoId": "56B44F6D10557CC6"]]],
    ]

    @Test func anAddNamesTheEntryItMade() {
        #expect(YTMusicClient.addedSongs(in: addedResponse, playlistId: "PLmine")
            == [.init(videoId: "tuw1ziytBDk", entry: PlaylistEntry(playlistId: "PLmine", setVideoId: "56B44F6D10557CC6"))])
        #expect(YTMusicClient.addedSongs(in: ["status": "STATUS_SUCCEEDED"], playlistId: "PLmine").isEmpty,
                "a song skipped as already there made no entry")
    }

    @Test func undoingAnAddTakesOutThatEntry() async throws {
        var calls: [(String, [String: Any])] = []
        let response = addedResponse
        let music = YTMusicClient(auth: AuthService(), write: { endpoint, body in
            calls.append((endpoint, body))
            return JSONObject(value: response)
        })
        let playlist = OwnPlaylist(id: "PLmine", title: "run")
        let center = notices()
        RowMenu.add(schism, to: playlist, music: music, notices: center)
        for _ in 0..<50 where center.current == nil { try await Task.sleep(for: .milliseconds(10)) }
        #expect(center.current?.spoken == "Added \(schism.title) to run")
        #expect(music.addedTo[schism.id] == ["PLmine"])
        center.performAction()
        for _ in 0..<50 where calls.count < 2 { try await Task.sleep(for: .milliseconds(10)) }
        let body = try #require(calls.last?.1)
        #expect(JSON.string(body["playlistId"]) == "PLmine")
        let action = try #require(JSON.array(body["actions"])?.first.flatMap(JSON.dict))
        #expect(JSON.string(action["action"]) == "ACTION_REMOVE_VIDEO")
        #expect(JSON.string(action["setVideoId"]) == "56B44F6D10557CC6")
        #expect(JSON.string(action["removedVideoId"]) == schism.id)
        #expect(music.addedTo[schism.id]?.contains("PLmine") != true, "the menu stops ticking it")
    }

    @Test func anAddThatMadeNoEntryOffersNoUndo() async throws {
        let music = YTMusicClient(auth: AuthService(), write: { _, _ in JSONObject(value: [:]) })
        let center = notices()
        RowMenu.add(schism, to: OwnPlaylist(id: "PLmine", title: "run"), music: music, notices: center)
        for _ in 0..<50 where center.current == nil { try await Task.sleep(for: .milliseconds(10)) }
        #expect(center.current?.spoken == "Added \(schism.title) to run")
        #expect(center.current?.action == nil)
    }

    @Test func aFailedWritePostsNothing() async throws {
        let music = YTMusicClient(auth: AuthService(), write: { _, _ in throw URLError(.notConnectedToInternet) })
        let center = notices()
        RowMenu.add(schism, to: OwnPlaylist(id: "PLmine", title: "run"), music: music, notices: center)
        try await Task.sleep(for: .milliseconds(100))
        #expect(center.current == nil)
    }
}
