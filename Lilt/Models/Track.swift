import Foundation

struct Track: Identifiable, Hashable, Sendable {
    /// YouTube video id.
    let id: String
    var title: String
    var artist: String
    var album: String?
    var durationText: String?
    var artworkURL: URL?
}
