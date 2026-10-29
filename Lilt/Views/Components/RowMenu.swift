import AppKit
import SwiftUI

/// One entry in a row's right-click menu.
enum RowAction: Hashable {
    case play, shuffle, playNext, addToQueue
    case addToPlaylist, removeFromPlaylist
    case like, unlike
    case saveToLibrary, subscribe
    case goToArtist, goToAlbum
    case copyLink

    var title: String {
        switch self {
        case .play: "Play"
        case .shuffle: "Shuffle"
        case .playNext: "Play Next"
        case .addToQueue: "Add to Queue"
        case .addToPlaylist: "Add to Playlist…"
        case .removeFromPlaylist: "Remove from Playlist"
        case .like: "Like"
        case .unlike: "Remove from Liked Music"
        case .saveToLibrary: "Save to Library"
        case .subscribe: "Subscribe"
        case .goToArtist: "Go to Artist"
        case .goToAlbum: "Go to Album"
        case .copyLink: "Copy Link"
        }
    }

    /// Shown but not wired up yet: these need write calls to YouTube Music that Lilt doesn't
    /// make so far. They show greyed out until they do.
    var isStub: Bool {
        switch self {
        case .playNext, .addToPlaylist, .removeFromPlaylist, .like, .unlike, .saveToLibrary, .subscribe: true
        default: false
        }
    }
}

/// What a row's right-click menu offers: groups of actions, split by dividers. Depends on what
/// the row is and on the list it sits in (a playlist's own tracks can come out of it).
enum RowMenu {
    /// Liked Music's browse id. Its tracks leave it by being unliked, not by playlist edits.
    static let likedMusicId = "VLLM"

    static func track(_ track: Track, in source: BrowseItem?) -> [[RowAction]] {
        var playlist: [RowAction] = [.addToPlaylist]
        var library: [RowAction] = [.like]
        if source?.id == likedMusicId {
            library = [.unlike]
        } else if source?.kind == .playlist {
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
            return [[.play, .shuffle], [.subscribe], [.copyLink]]
        case .album, .playlist:
            let go: [RowAction] = item.artistItem != nil ? [.goToArtist] : []
            return [[.play, .shuffle, .playNext, .addToQueue], [.addToPlaylist, .saveToLibrary], go, [.copyLink]].filter { !$0.isEmpty }
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

/// Renders a row's actions as menu items; `perform` handles the live ones.
struct RowMenuItems: View {
    let groups: [[RowAction]]
    let perform: (RowAction) -> Void

    var body: some View {
        ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
            if index > 0 { Divider() }
            ForEach(group, id: \.self) { action in
                Button(action.title) { perform(action) }
                    .disabled(action.isStub)
            }
        }
    }
}
