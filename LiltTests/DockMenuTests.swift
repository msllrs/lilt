import AppKit
import Foundation
import Testing
@testable import Lilt

/// The Dock tile's menu: playback, then what the bar's own right-click menu offers for the song.
@MainActor
struct DockMenuTests {
    private let song = Track(id: "v1", title: "Schism", artist: "Tool", album: "Lateralus", artistId: "UCtool", albumId: "MPREb-lateralus")

    /// A player resumed on `queue[0]`, without loading anything into the web player. The real
    /// app's saved playback is put back afterwards.
    private func withPlayer(_ queue: [Track], _ body: (PlayerService) throws -> Void) throws {
        let key = "playbackState"
        let saved = UserDefaults.standard.data(forKey: key)
        defer { if let saved { UserDefaults.standard.set(saved, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) } }
        let state: [String: Any] = ["queue": try JSONSerialization.jsonObject(with: JSONEncoder().encode(queue)), "index": 0, "time": 0]
        UserDefaults.standard.set(try JSONSerialization.data(withJSONObject: state), forKey: key)
        try body(PlayerService(auth: AuthService()))
    }

    private func menu(_ player: PlayerService) -> NSMenu {
        DockMenu.build(player: player, music: YTMusicClient(auth: AuthService()), recents: RecentsStore(), actions: .none)
    }

    private func titles(_ menu: NSMenu) -> [String] { menu.items.map { $0.isSeparatorItem ? "—" : $0.title } }

    @Test func nothingLoadedOffersOnlyTheApp() throws {
        try withPlayer([]) { player in
            #expect(titles(menu(player)) == ["Show Lilt"])
        }
    }

    @Test func theSongsOwnActionsFollowPlayback() throws {
        try withPlayer([song]) { player in
            let menu = menu(player)
            let all = titles(menu)
            #expect(all.first == "Schism — Tool")
            for title in ["Pause", "Next", "Previous"] where title != "Pause" { #expect(all.contains(title)) }
            #expect(all.contains("Like"))
            #expect(all.contains("Add to Playlist"))
            #expect(all.contains("Go to Artist") && all.contains("Go to Album"))
            #expect(all.contains("Copy Link"))
            #expect(all.last == "Show Lilt")
            // Your playlists come in a submenu, still loading on a first open.
            let playlists = try #require(menu.item(withTitle: "Add to Playlist")?.submenu)
            #expect(playlists.items.map(\.title) == ["Loading Playlists…"])
        }
    }

    @Test func aLikedSongOffersToUnlike() throws {
        try withPlayer([song]) { player in
            player.toggleLike()
            #expect(titles(menu(player)).contains("Remove from Liked Music"))
        }
    }
}

/// Shuffle and repeat, ticked to show what's on.
@MainActor
struct DockMenuPlaybackModeTests {
    private let song = Track(id: "v1", title: "Schism", artist: "Tool")

    private func withPlayer(_ body: (PlayerService) throws -> Void) throws {
        let key = "playbackState"
        let saved = UserDefaults.standard.data(forKey: key)
        defer { if let saved { UserDefaults.standard.set(saved, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) } }
        let state: [String: Any] = ["queue": try JSONSerialization.jsonObject(with: JSONEncoder().encode([song])), "index": 0, "time": 0]
        UserDefaults.standard.set(try JSONSerialization.data(withJSONObject: state), forKey: key)
        try body(PlayerService(auth: AuthService()))
    }

    private func menu(_ player: PlayerService) -> NSMenu {
        DockMenu.build(player: player, music: YTMusicClient(auth: AuthService()), recents: RecentsStore(), actions: .none)
    }

    @Test func shuffleIsTickedWhenOn() throws {
        try withPlayer { player in
            #expect(menu(player).item(withTitle: "Shuffle")?.state == .off)
            player.toggleShuffle()
            #expect(menu(player).item(withTitle: "Shuffle")?.state == .on)
        }
    }

    @Test func repeatTicksTheModeInUse() throws {
        try withPlayer { player in
            let modes = try #require(menu(player).item(withTitle: "Repeat")?.submenu)
            #expect(modes.items.map(\.title) == ["Off", "All", "One"])
            #expect(modes.items.map(\.state) == [.on, .off, .off])
            player.setRepeat(.one)
            #expect(try #require(menu(player).item(withTitle: "Repeat")?.submenu).items.map(\.state) == [.off, .off, .on])
        }
    }
}

/// What's coming up, and what played before, each a submenu to jump straight to a song.
@MainActor
struct DockMenuQueueTests {
    private func song(_ id: String) -> Track { Track(id: id, title: id, artist: "Tool") }

    private func withPlayer(_ queue: [Track], _ body: (PlayerService) throws -> Void) throws {
        let key = "playbackState"
        let saved = UserDefaults.standard.data(forKey: key)
        defer { if let saved { UserDefaults.standard.set(saved, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) } }
        let state: [String: Any] = ["queue": try JSONSerialization.jsonObject(with: JSONEncoder().encode(queue)), "index": 0, "time": 0]
        UserDefaults.standard.set(try JSONSerialization.data(withJSONObject: state), forKey: key)
        try body(PlayerService(auth: AuthService()))
    }

    private func menu(_ player: PlayerService) -> NSMenu {
        DockMenu.build(player: player, music: YTMusicClient(auth: AuthService()), recents: RecentsStore(), actions: .none)
    }

    @Test func upNextListsYourAddsThenTheList() throws {
        try withPlayer([song("now"), song("list1"), song("list2")]) { player in
            player.enqueue(song("queued"))
            let upNext = try #require(menu(player).item(withTitle: "Up Next")?.submenu)
            #expect(upNext.items.map { $0.isSeparatorItem ? "—" : $0.title } == ["queued — Tool", "—", "list1 — Tool", "list2 — Tool"])
        }
    }

    @Test func nothingUpNextLeavesItOut() throws {
        try withPlayer([song("now")]) { player in
            #expect(menu(player).item(withTitle: "Up Next") == nil)
        }
    }

    @Test func upNextIsCapped() throws {
        try withPlayer([song("now")] + (1...30).map { song("s\($0)") }) { player in
            let upNext = try #require(menu(player).item(withTitle: "Up Next")?.submenu)
            #expect(upNext.items.count == DockMenu.upNextShown)
        }
    }
}
