import Foundation
import Observation

/// Playback state and queue. Lilt's queue is the source of truth: next/previous navigate the
/// hidden web view explicitly rather than trusting YouTube Music's own autoplay.
@MainActor
@Observable
final class PlayerService {
    private(set) var queue: [Track] = []
    private(set) var currentIndex: Int?
    private(set) var isPlaying = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0

    /// Metadata as reported by the web player; falls back to the queued track.
    private(set) var liveTitle = ""
    private(set) var liveArtist = ""
    private(set) var liveArtworkURL: URL?

    var current: Track? {
        guard let i = currentIndex, queue.indices.contains(i) else { return nil }
        return queue[i]
    }
    var hasNext: Bool { currentIndex.map { $0 + 1 < queue.count } ?? false }
    var hasPrevious: Bool { currentIndex.map { $0 > 0 } ?? false }
    var displayTitle: String { liveTitle.isEmpty ? (current?.title ?? "") : liveTitle }
    var displayArtist: String { liveArtist.isEmpty ? (current?.artist ?? "") : liveArtist }
    var displayArtworkURL: URL? { liveArtworkURL ?? current?.artworkURL }

    let bridge: PlayerBridge
    private let nowPlaying = NowPlayingManager()

    /// True between asking the web view to load a track and seeing state for that track.
    private var isLoading = false
    /// Nudge playback once if the page loads paused (YouTube occasionally waits for a gesture).
    private var wantsAutoplayNudge = false

    init(auth: AuthService) {
        bridge = PlayerBridge(dataStore: auth.dataStore)
        nowPlaying.player = self
        bridge.onEvent = { [weak self] event in self?.handle(event) }
    }

    // MARK: Commands

    func play(_ tracks: [Track], startingAt index: Int) {
        guard tracks.indices.contains(index) else { return }
        queue = tracks
        load(index: index)
    }

    func togglePlayPause() {
        isPlaying ? pause() : resume()
    }

    func resume() {
        guard current != nil else { return }
        bridge.play()
    }

    func pause() {
        bridge.pause()
    }

    func next() {
        guard let i = currentIndex, i + 1 < queue.count else { return }
        load(index: i + 1)
    }

    func previous() {
        guard let i = currentIndex else { return }
        if currentTime > 3 || i == 0 {
            seek(to: 0)
        } else {
            load(index: i - 1)
        }
    }

    func seek(to seconds: Double) {
        currentTime = seconds
        bridge.seek(to: seconds)
    }

    func stop() {
        queue = []
        currentIndex = nil
        resetLiveState()
        bridge.unload()
        publishNowPlaying()
    }

    // MARK: Internals

    private func load(index: Int) {
        currentIndex = index
        resetLiveState()
        isLoading = true
        wantsAutoplayNudge = true
        bridge.load(videoId: queue[index].id)
        publishNowPlaying()
    }

    private func resetLiveState() {
        isPlaying = false
        currentTime = 0
        duration = 0
        liveTitle = ""
        liveArtist = ""
        liveArtworkURL = nil
    }

    private func handle(_ event: PlayerEvent) {
        switch event {
        case .ready:
            break
        case .ended(let videoId):
            guard videoId == current?.id else { return }
            if hasNext {
                next()
            } else {
                // Let YouTube Music continue with its own pick; `adopt` picks it up.
                isLoading = false
            }
        case .state(let s):
            apply(s)
        }
    }

    private func apply(_ s: PlaybackSnapshot) {
        guard let videoId = s.videoId else { return }
        if videoId != current?.id {
            // Stale state from the previous document while a load is in flight.
            if isLoading { return }
            adopt(videoId: videoId, from: s)
        }
        isLoading = false
        isPlaying = s.isPlaying
        currentTime = s.currentTime
        duration = s.duration
        liveTitle = s.title
        liveArtist = s.artist
        liveArtworkURL = s.artworkURL ?? liveArtworkURL

        if wantsAutoplayNudge {
            if s.isPlaying {
                wantsAutoplayNudge = false
            } else if s.duration > 0 {
                wantsAutoplayNudge = false
                bridge.play()
            }
        }
        publishNowPlaying()
    }

    /// YouTube Music moved on to a track we didn't queue (its radio continuation). Append it so
    /// the UI follows along.
    private func adopt(videoId: String, from s: PlaybackSnapshot) {
        let track = Track(id: videoId, title: s.title, artist: s.artist, artworkURL: s.artworkURL)
        if let i = currentIndex {
            queue.insert(track, at: i + 1)
            currentIndex = i + 1
        } else {
            queue.append(track)
            currentIndex = queue.count - 1
        }
    }

    private func publishNowPlaying() {
        nowPlaying.update(
            track: current,
            title: displayTitle,
            artist: displayArtist,
            artworkURL: displayArtworkURL,
            isPlaying: isPlaying,
            currentTime: currentTime,
            duration: duration
        )
    }
}
