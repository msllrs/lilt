import Foundation

enum BrowseKind: String, Codable, Sendable {
    case artist, album, playlist
}

/// Something you can open: an artist, album or playlist page.
struct BrowseItem: Identifiable, Hashable, Codable, Sendable {
    /// InnerTube browse id (UC… artist, MPREb… album, VL… playlist).
    let id: String
    let kind: BrowseKind
    var title: String
    var subtitle: String
    var artworkURL: URL?
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

struct BrowseSection: Identifiable, Hashable, Sendable {
    var id: String { title }
    let title: String
    var items: [BrowseItem]
}

/// A parsed artist, album or playlist page.
struct BrowsePage: Sendable {
    var item: BrowseItem
    var tracks: [Track] = []
    /// For artists: the browse id of the "all songs" playlist, when YouTube offers one.
    var allSongsId: String?
    /// For albums: the primary artist, used to fill the page out with related content.
    var artistId: String?
    var sections: [BrowseSection] = []
}
