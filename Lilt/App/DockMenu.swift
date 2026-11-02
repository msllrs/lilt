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

    static func build(player: PlayerService, music: YTMusicClient, recents: RecentsStore, actions: Actions) -> NSMenu {
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
            addSongActions(for: track, to: menu, player: player, music: music, actions: actions)
            menu.addItem(.separator())
            addPlaybackModes(to: menu, player: player)
            menu.addItem(.separator())
        }
        menu.addItem(ActionItem("Show Lilt", perform: actions.show))
        return menu
    }

    /// The bar's right-click menu for the playing song, as Dock menu items.
    private static func addSongActions(for track: Track, to menu: NSMenu, player: PlayerService, music: YTMusicClient, actions: Actions) {
        for action in RowMenu.nowPlaying(track, isLiked: player.isLiked).joined() {
            switch action {
            case .addToPlaylist:
                menu.addItem(playlistMenu(for: track, music: music))
            case .like, .unlike:
                menu.addItem(ActionItem(action.title) { RowMenu.setLiked(action == .like, track, player: player, music: music) })
            case .goToArtist:
                menu.addItem(ActionItem(action.title) { if let item = track.artistItem { actions.open(item) } })
            case .goToAlbum:
                menu.addItem(ActionItem(action.title) { if let item = track.albumItem { actions.open(item) } })
            case .copyLink:
                menu.addItem(ActionItem(action.title) { RowMenu.copy(RowMenu.webURL(for: track)) })
            default:
                break
            }
        }
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
    private static func playlistMenu(for track: Track, music: YTMusicClient) -> NSMenuItem {
        let item = NSMenuItem(title: RowAction.addToPlaylist.title, action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        if music.ownPlaylists.isEmpty {
            let loading = NSMenuItem(title: "Loading Playlists…", action: nil, keyEquivalent: "")
            loading.isEnabled = false
            submenu.addItem(loading)
        }
        let added = music.addedTo[track.id] ?? []
        for playlist in music.ownPlaylists {
            let entry = ActionItem(playlist.title) { Task { try? await music.add(track, to: playlist) } }
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
