import SwiftUI

/// Rows for a list of tracks; tapping one plays it with the list as the queue.
struct TrackRows: View {
    /// Settings ▸ Appearance ▸ Hide unavailable songs.
    static let hidesUnavailableKey = "hidesUnavailableSongs"

    @Environment(\.hidesUnavailableSongs) private var hidesUnavailable
    let tracks: [Track]
    /// When set, render just this one track (still queued with the whole list). Lets a mixed
    /// list interleave track rows with other rows while keeping the shelf as the queue.
    var only: Track? = nil
    /// The page these tracks belong to, when they are its contents.
    var source: BrowseItem? = nil

    /// The rows shown, which are also the queue a click plays.
    private var shown: [Track] { hidesUnavailable ? tracks.filter { $0.isUnavailable != true } : tracks }

    var body: some View {
        let tracks = shown
        ForEach(Array(tracks.enumerated()), id: \.element.rowId) { index, track in
            #if DEBUG
            let _ = RowBuildCounts.noteSlot(track)
            #endif
            if only == nil || only?.id == track.id {
                QueuedTrackRow(queue: tracks, index: index, source: source)
            }
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
/// as a hitch. Keyed by song, so tests running alongside don't count each other's rows.
@MainActor
enum RowBuildCounts {
    static var rows: [String: Int] = [:]
    static var slots: [String: Int] = [:]

    static func noteRow(_ track: Track) { rows[track.id, default: 0] += 1 }
    static func noteSlot(_ track: Track) { slots[track.id, default: 0] += 1 }
}
#endif
