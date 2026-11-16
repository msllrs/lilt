import Foundation

/// Artist and album links for a track, resolved from InnerTube when a row didn't carry them.
struct TrackLinks: Sendable {
    var artist: String?
    var artistId: String?
    var album: String?
    var albumId: String?
}

/// A playlist of yours that songs can be added to.
struct OwnPlaylist: Identifiable, Hashable, Sendable {
    /// The playlist id (PL…), without the browse id's "VL".
    let id: String
    var title: String
}

/// One song's place in a playlist, which is what removing it from the playlist names.
struct PlaylistEntry: Hashable, Codable, Sendable {
    var playlistId: String
    var setVideoId: String
}

struct Track: Identifiable, Hashable, Codable, Sendable {
    /// YouTube video id.
    let id: String
    var title: String
    var artist: String
    var album: String?
    var durationText: String?
    var artworkURL: URL?
    /// Browse id of the primary artist (UC…), when known.
    var artistId: String?
    /// Browse id of the album (MPREb…), when known.
    var albumId: String?
    /// Whether you've liked it, when the response said.
    var isLiked: Bool?
    /// Where this song sits in a playlist you can edit. Only your own playlists' rows carry it.
    var playlistEntry: PlaylistEntry?
    /// This row's own id in its playlist (`playlistSetVideoId`), which tells two entries of the
    /// same song apart. `id` stays the song's, which is what plays.
    var entryId: String? = nil
    /// YouTube Music's explicit badge.
    var isExplicit: Bool? = nil
    /// Greyed out by YouTube Music: listed, but it can't be played here (taken down, or not
    /// licensed in this country).
    var isUnavailable: Bool? = nil

    /// What tells this row from the others in its list: its playlist entry, else the song.
    var rowId: String { entryId ?? id }

    var artistItem: BrowseItem? {
        guard let artistId else { return nil }
        return BrowseItem(id: artistId, kind: .artist, title: artist, subtitle: "Artist", artworkURL: nil)
    }

    var albumItem: BrowseItem? {
        guard let albumId else { return nil }
        return BrowseItem(id: albumId, kind: .album, title: album ?? "", subtitle: artist, artworkURL: artworkURL)
    }
}
