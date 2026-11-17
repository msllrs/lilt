import SwiftUI

/// Rows for a list of tracks; tapping one plays it with the list as the queue.
struct TrackRows: View {
    /// Settings ▸ Appearance ▸ Hide unavailable songs.
    static let hidesUnavailableKey = "hidesUnavailableSongs"

    @Environment(\.hidesUnavailableSongs) private var hidesUnavailable
    let tracks: [Track]
    /// The page these tracks belong to, when they are its contents.
    var source: BrowseItem? = nil

    /// The rows shown, which are also the queue a click plays.
    private var shown: [Track] { SongShelf.shown(tracks, hidingUnavailable: hidesUnavailable) }

    var body: some View {
        let tracks = shown
        ForEach(Array(tracks.enumerated()), id: \.element.rowId) { index, track in
            #if DEBUG
            let _ = RowBuildCounts.noteSlot(track)
            #endif
            QueuedTrackRow(queue: tracks, index: index, source: source)
        }
    }
}

/// One song of a list, which a click plays with the list as the queue. The player is read here,
/// row by row, rather than by the list: a song change or a pause then reruns these small bodies
/// and nothing around them, and hands on whether it's playing to the playing row alone, so the
/// rest compare unchanged and aren't rebuilt.
struct QueuedTrackRow: View {
    let queue: [Track]
    let index: Int
    var source: BrowseItem? = nil

    @Environment(PlayerService.self) private var player

    var body: some View {
        let track = queue[index]
        let isCurrent = player.current?.id == track.id
        TrackRow(track: track, isCurrent: isCurrent, isPlaying: isCurrent && player.isPlaying, source: source) {
            player.play(queue, startingAt: index, source: source)
        }
        // Under a page's section header (row 0) when the page staggers its rows in.
        .entrance(.row(index + 1))
    }
}

/// The songs of a shelf that mixes them with other rows (Home, Search), worked out once for the
/// shelf: which show, and where each sits among them, which is where playing it starts the
/// shelf from. Each song used to go through the whole shelf to find itself, a shelf of twenty
/// building four hundred rows' worth of list to show twenty.
struct SongShelf {
    /// The songs shown, which are also the queue a click plays.
    let shown: [Track]
    private let places: [String: Int]

    init(_ tracks: [Track], hidingUnavailable: Bool) {
        shown = Self.shown(tracks, hidingUnavailable: hidingUnavailable)
        places = Dictionary(shown.enumerated().map { ($1.rowId, $0) }, uniquingKeysWith: { first, _ in first })
    }

    static func shown(_ tracks: [Track], hidingUnavailable: Bool) -> [Track] {
        hidingUnavailable ? tracks.filter { $0.isUnavailable != true } : tracks
    }

    /// The song's row, queued with the rest of the shelf; nothing when the shelf leaves it out.
    @MainActor @ViewBuilder
    func row(for track: Track) -> some View {
        #if DEBUG
        let _ = RowBuildCounts.noteSlot(track)
        #endif
        if let index = places[track.rowId] {
            QueuedTrackRow(queue: shown, index: index)
        }
    }
}

struct TrackList: View {
    let tracks: [Track]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                TrackRows(tracks: tracks)
            }
            .padding(.horizontal, Theme.Space.rowInset)
            .padding(.bottom, Theme.Space.sm)
        }
        .scrollIndicators(.never)
        .panelScrollEdge()
    }
}

#if DEBUG
/// How many times each song's row has been built, and its place in a list gone through, by
/// video id. Tests read it to check that a change rebuilds only the rows it touches: play/pause
/// re-running every row on screen, or a shelf going through all its songs for each one, is felt
/// as a hitch. Keyed by song, so tests running alongside don't count each other's rows. Album,
/// playlist and artist rows are counted the same way, by browse id.
@MainActor
enum RowBuildCounts {
    static var rows: [String: Int] = [:]
    static var slots: [String: Int] = [:]
    static var items: [String: Int] = [:]

    static func noteRow(_ track: Track) { rows[track.id, default: 0] += 1 }
    static func noteSlot(_ track: Track) { slots[track.id, default: 0] += 1 }
    static func noteItem(_ item: BrowseItem) { items[item.id, default: 0] += 1 }

    /// The parts of a row that only a hovered, playing or shining row shows, by name, built
    /// while `countsParts` is on. A row coming into a list for the first time builds every part
    /// it holds, shown or not, so each one a resting row holds for nothing is paid for row by row
    /// on a long list's first scroll. Counted only while a test asks, since no row says whose
    /// part it is.
    static var parts: [String: Int] = [:]
    static var countsParts = false
    static func notePart(_ name: String) { if countsParts { parts[name, default: 0] += 1 } }
}
#endif
