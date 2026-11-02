import AppKit

/// The Dock tile's menu. AppKit asks for it each time it opens, so it's built fresh from the
/// player's state: the song, playback, then the song's own actions, the same ones the
/// now-playing bar's right-click menu offers.
@MainActor
enum DockMenu {
    /// What the menu's items do beyond the player itself. Opening a page and showing the panel
    /// belong to the app delegate.
    struct Actions {
        var open: (BrowseItem) -> Void
        var show: () -> Void

        @MainActor static let none = Actions(open: { _ in }, show: {})
    }

    /// `notices` confirms the song's actions in the panel; it stays silent while the panel is
    /// out of sight, which it often is when the Dock menu is used.
    static func build(player: PlayerService, music: YTMusicClient, recents: RecentsStore, actions: Actions, notices: NoticeCenter? = nil) -> NSMenu {
        let menu = NSMenu()
        if let current = player.current {
            let track = music.withLinks(current)
            let title = NSMenuItem(title: "\(track.title) — \(track.artist)", action: nil, keyEquivalent: "")
            title.isEnabled = false
            menu.addItem(title)
            menu.addItem(.separator())
            menu.addItem(ActionItem(player.isPlaying ? "Pause" : "Play") { player.togglePlayPause() })
            let next = ActionItem("Next") { player.next() }
            next.isEnabled = player.hasNext
            menu.addItem(next)
            menu.addItem(ActionItem("Previous") { player.previous() })
            menu.addItem(.separator())
            addSongActions(for: track, to: menu, player: player, music: music, actions: actions, notices: notices)
            menu.addItem(.separator())
            addPlaybackModes(to: menu, player: player)
            menu.addItem(.separator())
            let lists = [upNextMenu(player: player), recentlyPlayedMenu(player: player, recents: recents)].compactMap { $0 }
            for list in lists { menu.addItem(list) }
            if !lists.isEmpty { menu.addItem(.separator()) }
        }
        menu.addItem(ActionItem("Show Lilt", perform: actions.show))
        return menu
    }

    /// The bar's right-click menu for the playing song, as Dock menu items.
    private static func addSongActions(for track: Track, to menu: NSMenu, player: PlayerService, music: YTMusicClient, actions: Actions, notices: NoticeCenter?) {
        for action in RowMenu.nowPlaying(track, isLiked: player.isLiked).joined() {
            switch action {
            case .addToPlaylist:
                menu.addItem(playlistMenu(for: track, music: music, notices: notices))
            case .like, .unlike:
                menu.addItem(ActionItem(action.title) { RowMenu.setLiked(action == .like, track, player: player, music: music, notices: notices) })
            case .goToArtist:
                menu.addItem(ActionItem(action.title) { if let item = track.artistItem { actions.open(item) } })
            case .goToAlbum:
                menu.addItem(ActionItem(action.title) { if let item = track.albumItem { actions.open(item) } })
            case .copyLink:
                menu.addItem(ActionItem(action.title) { RowMenu.copyLink(RowMenu.webURL(for: track), named: track.title, notices: notices) })
            default:
                break
            }
        }
    }

    /// How many songs the Up Next submenu lists, your adds first.
    static let upNextShown = 10

    /// What plays next: your adds, then the rest of the list you started from. Choosing one
    /// jumps to it, as clicking it in the queue does. Nil when nothing follows.
    private static func upNextMenu(player: PlayerService) -> NSMenuItem? {
        let manual = Array(player.upcoming.prefix(upNextShown).enumerated())
        let automatic = Array(player.automaticUpcoming.prefix(upNextShown - manual.count).enumerated())
        guard !manual.isEmpty || !automatic.isEmpty else { return nil }
        let submenu = NSMenu()
        for (offset, track) in manual {
            submenu.addItem(ActionItem(label(track)) { player.playUpcoming(at: offset) })
        }
        // The separator takes a slot, so the cap holds for the whole list.
        if !manual.isEmpty, !automatic.isEmpty { submenu.addItem(.separator()) }
        for (offset, track) in automatic.prefix(upNextShown - submenu.items.count) {
            submenu.addItem(ActionItem(label(track)) { player.playAutomatic(at: offset) })
        }
        let item = NSMenuItem(title: "Up Next", action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    /// The songs played before this one, most recent first, with the covers the clock menu
    /// keeps. Choosing one starts it on its own, as the clock menu does. Nil when there are none.
    private static func recentlyPlayedMenu(player: PlayerService, recents: RecentsStore) -> NSMenuItem? {
        let played = recents.played.filter { $0.id != player.current?.id }
        guard !played.isEmpty else { return nil }
        let submenu = NSMenu()
        for track in played {
            let entry = ActionItem(label(track)) { player.play([track], startingAt: 0) }
            entry.image = recents.thumbnail(for: track.id)
            submenu.addItem(entry)
        }
        let item = NSMenuItem(title: "Recently Played", action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    private static func label(_ track: Track) -> String {
        track.artist.isEmpty ? track.title : "\(track.title) — \(track.artist)"
    }

    /// Shuffle, and the repeat modes in a submenu, each ticked when on.
    private static func addPlaybackModes(to menu: NSMenu, player: PlayerService) {
        let shuffle = ActionItem("Shuffle") { player.toggleShuffle() }
        shuffle.state = player.isShuffled ? .on : .off
        menu.addItem(shuffle)
        let item = NSMenuItem(title: "Repeat", action: nil, keyEquivalent: "")
        let modes = NSMenu()
        for (mode, title) in [(PlayerService.RepeatMode.off, "Off"), (.all, "All"), (.one, "One")] {
            let entry = ActionItem(title) { player.setRepeat(mode) }
            entry.state = player.repeatMode == mode ? .on : .off
            modes.addItem(entry)
        }
        item.submenu = modes
        menu.addItem(item)
    }

    /// Your playlists, ticking the ones the song was added to. The Dock shows a snapshot of the
    /// menu, so a list still loading can't fill in while it's open; the app warms it as each
    /// song starts.
    private static func playlistMenu(for track: Track, music: YTMusicClient, notices: NoticeCenter?) -> NSMenuItem {
        let item = NSMenuItem(title: RowAction.addToPlaylist.title, action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        if music.ownPlaylists.isEmpty {
            let loading = NSMenuItem(title: "Loading Playlists…", action: nil, keyEquivalent: "")
            loading.isEnabled = false
            submenu.addItem(loading)
        }
        let added = music.addedTo[track.id] ?? []
        for playlist in music.ownPlaylists {
            let entry = ActionItem(playlist.title) { RowMenu.add(track, to: playlist, music: music, notices: notices) }
            entry.state = added.contains(playlist.id) ? .on : .off
            submenu.addItem(entry)
        }
        item.submenu = submenu
        return item
    }
}

/// A menu item that runs a closure: the Dock menu's actions reach the player and the music
/// client directly, without a selector on the app delegate for each.
final class ActionItem: NSMenuItem {
    private let perform: () -> Void

    init(_ title: String, perform: @escaping () -> Void) {
        self.perform = perform
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func run() { perform() }
}
