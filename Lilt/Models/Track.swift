import Foundation

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

    var artistItem: BrowseItem? {
        guard let artistId else { return nil }
        return BrowseItem(id: artistId, kind: .artist, title: artist, subtitle: "Artist", artworkURL: nil)
    }
}
