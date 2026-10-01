import SwiftUI

/// Rows for a list of tracks; tapping one plays it with the list as the queue.
struct TrackRows: View {
    @Environment(PlayerService.self) private var player
    let tracks: [Track]

    var body: some View {
        ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
            TrackRow(
                track: track,
                isCurrent: player.current?.id == track.id,
                isPlaying: player.isPlaying
            ) {
                player.play(tracks, startingAt: index)
            }
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
        .scrollEdgeEffectStyle(.soft, for: .all)
    }
}
