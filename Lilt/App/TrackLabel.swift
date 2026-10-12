/// A track as one line of text, for the places that name Lilt while you aren't looking at it:
/// the panel's window title (Mission Control, the Window menu, the Dock menu's window list) and
/// the Dock menu's Now Playing entry.
enum TrackLabel {
    /// "Title – Artist", or whichever of the two isn't blank; nil for no track.
    static func text(for track: Track?) -> String? {
        guard let track else { return nil }
        let title = track.title.trimmingCharacters(in: .whitespaces)
        let artist = track.artist.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return artist.isEmpty ? nil : artist }
        return artist.isEmpty ? title : "\(title) – \(artist)"
    }
}
