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
            #expect(all.contains("Start Mix"))
            #expect(all.contains("Add to Playlist"))
            #expect(all.contains("Go to Artist") && all.contains("Go to Album"))
            #expect(all.contains("Copy Link"))
            #expect(all.last == "Show Lilt")
            // Your playlists come in a submenu, still loading on a first open.
            let playlists = try #require(menu.item(withTitle: "Add to Playlist")?.submenu)
            #expect(playlists.items.map(\.title) == ["Loading Playlists…"])
        }
    }

    /// As laid out on 2026-11-06: the mix first, under the song; then playback, its modes, the
    /// song's like and playlists, where it's from, and its link, each group divided.
    @Test func theMenuIsGroupedAsLaidOut() throws {
        try withPlayer([song]) { player in
            let laidOut = [
                "Schism — Tool", "—",
                "Start Mix", "—",
                "Play", "Next", "Previous", "—",
                "Shuffle", "Repeat", "—",
                "Like", "Add to Playlist", "—",
                "Go to Artist", "Go to Album", "—",
                "Copy Link", "—",
            ]
            // Recently Played may follow, from this Mac's own history, before Show Lilt.
            let all = titles(menu(player))
            #expect(Array(all.prefix(laidOut.count)) == laidOut)
            #expect(all.last == "Show Lilt")
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

/// The songs played before this one, to start one again.
@MainActor
struct DockMenuRecentsTests {
    private func song(_ id: String) -> Track { Track(id: id, title: id, artist: "Tool") }

    /// A player on `current` and recents holding `played`, most recent first. The real app's
    /// saved playback and recents are put back afterwards.
    private func withState(current: Track, played: [Track], _ body: (PlayerService, RecentsStore) throws -> Void) throws {
        let keys = ["playbackState", "recents"]
        let saved = keys.map { UserDefaults.standard.data(forKey: $0) }
        defer {
            for (key, data) in zip(keys, saved) {
                if let data { UserDefaults.standard.set(data, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
            }
        }
        let state: [String: Any] = ["queue": try JSONSerialization.jsonObject(with: JSONEncoder().encode([current])), "index": 0, "time": 0]
        UserDefaults.standard.set(try JSONSerialization.data(withJSONObject: state), forKey: "playbackState")
        let recents: [String: Any] = ["played": try JSONSerialization.jsonObject(with: JSONEncoder().encode(played)), "viewed": []]
        UserDefaults.standard.set(try JSONSerialization.data(withJSONObject: recents), forKey: "recents")
        try body(PlayerService(auth: AuthService()), RecentsStore())
    }

    @Test func recentlyPlayedLeavesOutTheSongPlayingNow() throws {
        try withState(current: song("now"), played: [song("now"), song("before"), song("earlier")]) { player, recents in
            let menu = DockMenu.build(player: player, music: YTMusicClient(auth: AuthService()), recents: recents, actions: .none)
            let played = try #require(menu.item(withTitle: "Recently Played")?.submenu)
            #expect(played.items.map(\.title) == ["before — Tool", "earlier — Tool"])
        }
    }

    @Test func nothingPlayedBeforeLeavesItOut() throws {
        try withState(current: song("now"), played: [song("now")]) { player, recents in
            let menu = DockMenu.build(player: player, music: YTMusicClient(auth: AuthService()), recents: recents, actions: .none)
            #expect(menu.item(withTitle: "Recently Played") == nil)
        }
    }
}
