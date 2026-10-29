import AppKit
import SwiftUI

/// One entry in a row's right-click menu.
enum RowAction: Hashable {
    case play, shuffle, playNext, addToQueue
    case addToPlaylist, removeFromPlaylist
    case like, unlike
    case goToArtist, goToAlbum
    case copyLink

    var title: String {
        switch self {
        case .play: "Play"
        case .shuffle: "Shuffle"
        case .playNext: "Play Next"
        case .addToQueue: "Add to Queue"
        case .addToPlaylist: "Add to Playlist"
        case .removeFromPlaylist: "Remove from Playlist"
        case .like: "Like"
        case .unlike: "Remove from Liked Music"
        case .goToArtist: "Go to Artist"
        case .goToAlbum: "Go to Album"
        case .copyLink: "Copy Link"
        }
    }
}

/// What a row's right-click menu offers: groups of actions, split by dividers. Depends on what
/// the row is and on the list it sits in (your own playlists' songs can come out of them).
enum RowMenu {
    /// `isLiked`: the song's like state as far as Lilt knows; nil when the response didn't say.
    static func track(_ track: Track, in source: BrowseItem?, isLiked: Bool? = nil) -> [[RowAction]] {
        var playlist: [RowAction] = [.addToPlaylist]
        // Liked Music's songs leave it by being unliked, not by playlist edits.
        let inLikedMusic = source.map(BrowseScreen.isLikedMusic) ?? false
        let library: [RowAction] = inLikedMusic || isLiked == true ? [.unlike] : [.like]
        if track.playlistEntry != nil, !inLikedMusic {
            playlist.append(.removeFromPlaylist)
        }
        var go: [RowAction] = []
        if track.artistItem != nil { go.append(.goToArtist) }
        // On the album's own page, going to the album goes nowhere.
        if let albumId = track.albumId, albumId != source?.id { go.append(.goToAlbum) }
        return [[.play, .playNext, .addToQueue], playlist, library, go, [.copyLink]].filter { !$0.isEmpty }
    }

    static func item(_ item: BrowseItem) -> [[RowAction]] {
        switch item.kind {
        case .artist:
            return [[.play, .shuffle], [.copyLink]]
        case .album, .playlist:
            let go: [RowAction] = item.artistItem != nil ? [.goToArtist] : []
            return [[.play, .shuffle, .playNext, .addToQueue], [.addToPlaylist], go, [.copyLink]].filter { !$0.isEmpty }
        case .library:
            return []
        }
    }

    /// The web address of a track or page on YouTube Music.
    static func webURL(for track: Track) -> URL? { URL(string: "https://music.youtube.com/watch?v=\(track.id)") }

    static func webURL(for item: BrowseItem) -> URL? {
        switch item.kind {
        case .artist: URL(string: "https://music.youtube.com/channel/\(item.id)")
        case .album: URL(string: "https://music.youtube.com/browse/\(item.id)")
        case .playlist: URL(string: "https://music.youtube.com/playlist?list=\(item.id.hasPrefix("VL") ? String(item.id.dropFirst(2)) : item.id)")
        case .library: nil
        }
    }

    static func copy(_ url: URL?) {
        guard let url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }
}

/// Renders a row's actions as menu items. Add to Playlist opens a submenu of your playlists,
/// ticking the ones the row has been added to.
struct RowMenuItems: View {
    let groups: [[RowAction]]
    var playlists: [OwnPlaylist] = []
    var addedTo: Set<String> = []
    let perform: (RowAction) -> Void
    var add: (OwnPlaylist) -> Void = { _ in }

    var body: some View {
        ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
            if index > 0 { Divider() }
            ForEach(group, id: \.self) { action in
                if action == .addToPlaylist {
                    playlistMenu
                } else {
                    Button(action.title) { perform(action) }
                }
            }
        }
    }

    private var playlistMenu: some View {
        Menu(RowAction.addToPlaylist.title) {
            if playlists.isEmpty {
                Button("Loading Playlists…") {}.disabled(true)
            }
            ForEach(playlists) { playlist in
                Button { add(playlist) } label: {
                    if addedTo.contains(playlist.id) { Label(playlist.title, systemImage: "checkmark") } else { Text(playlist.title) }
                }
            }
        }
    }
}
