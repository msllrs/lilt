import Foundation

enum BrowseKind: String, Codable, Sendable {
    case artist, album, playlist
    /// The signed-in library (playlists, albums, artists). Not a YouTube page of its own.
    case library
}

/// The Google account YouTube Music is answering for.
struct AccountInfo: Equatable, Codable, Sendable {
    var name: String
    var email: String
    var photoURL: URL?
    /// Other channels/brand accounts on this login, with the page id to select each (nil for
    /// the primary Google account).
    var alternatives: [Alternative] = []

    struct Alternative: Equatable, Codable, Sendable {
        var name: String
        var pageId: String?
    }
}

/// The signed-in library, gathered from several InnerTube browse endpoints.
struct LibraryContent: Codable, Equatable, Sendable {
    var playlists: [BrowseItem] = []
    var albums: [BrowseItem] = []
    var artists: [BrowseItem] = []

    var isEmpty: Bool { playlists.isEmpty && albums.isEmpty && artists.isEmpty }
}

/// Something you can open: an artist, album or playlist page.
struct BrowseItem: Identifiable, Hashable, Codable, Sendable {
    /// InnerTube browse id (UC… artist, MPREb… album, VL… playlist).
    let id: String
    let kind: BrowseKind
    var title: String
    var subtitle: String
    var artworkURL: URL?
    /// The artist named in `subtitle`, when YouTube linked one (albums, singles).
    var artist: String?
    var artistId: String?

    var artistItem: BrowseItem? {
        guard let artist, let artistId else { return nil }
        return BrowseItem(id: artistId, kind: .artist, title: artist, subtitle: "Artist", artworkURL: nil)
    }
}

struct SearchResults: Sendable {
    /// YouTube's own "top result" when it is an artist, album or playlist.
    var top: BrowseItem?
    var songs: [Track] = []
    var artists: [BrowseItem] = []
    var albums: [BrowseItem] = []
    var playlists: [BrowseItem] = []

    var isEmpty: Bool { top == nil && songs.isEmpty && artists.isEmpty && albums.isEmpty && playlists.isEmpty }
}

/// One entry on the home feed: a song to play or a page to open.
enum HomeItem: Identifiable, Hashable, Codable, Sendable {
    case track(Track)
    case browse(BrowseItem)

    var id: String {
        switch self {
        case .track(let track): "t:\(track.id)"
        case .browse(let item): "b:\(item.id)"
        }
    }
}

/// A shelf on the home feed ("Listen again", "Quick picks", "Mixed for you"…).
struct HomeSection: Identifiable, Hashable, Codable, Sendable {
    var id: String { title }
    let title: String
    var items: [HomeItem]

    var tracks: [Track] {
        items.compactMap { if case .track(let t) = $0 { t } else { nil } }
    }
}

struct BrowseSection: Identifiable, Hashable, Sendable {
    var id: String { title }
    let title: String
    var items: [BrowseItem]
}

/// A parsed artist, album or playlist page.
struct BrowsePage: Equatable, Sendable {
    var item: BrowseItem
    var tracks: [Track] = []
    /// For artists: the browse id of the "all songs" playlist, when YouTube offers one.
    var allSongsId: String?
    /// For albums: the primary artist, used to fill the page out with related content.
    var artistId: String?
    /// The playlist behind this page (a playlist's own id, or an album's audio playlist), which
    /// is what the library save call takes.
    var playlistId: String?
    /// For albums: the kind and year line ("Album • 2013") that the header shows under the
    /// artist, as playlists show theirs.
    var detail: String?
    /// For artists: the watch playlist of the header's Mix button (an RDEM… id), which isn't
    /// derived from the channel id and so has to come from the page.
    var radioId: String?
    var sections: [BrowseSection] = []
    /// Where the rest of a long list is: the token for its next page of songs, nil once the
    /// last page is in.
    var continuation: String?
}

/// YouTube Music's radio for a song, album, playlist or artist: a watch playlist that grows
/// from it, as the `next` endpoint gives it.
struct Mix: Equatable, Sendable {
    /// The watch playlist (RDAMVM…, RDAMPL…, RDEM…).
    var playlistId: String
    /// The panel's own name for it ("Mix – Schism"), when the response has one.
    var title: String?
    var tracks: [Track]
}
