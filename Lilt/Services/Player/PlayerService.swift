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
    // The queued track is the source of truth for what's shown: it's correct the instant you
    // click and its artwork is already cached. The web player's metadata lags a beat behind a
    // track change and serves a different image size, so it's only a fallback.
    var displayTitle: String {
        if let title = current?.title, !title.isEmpty { return title }
        return liveTitle
    }
    var displayArtist: String {
        if let artist = current?.artist, !artist.isEmpty { return artist }
        return liveArtist
    }
    var displayArtworkURL: URL? { current?.artworkURL ?? liveArtworkURL }

    let bridge: PlayerBridge
    /// Looks up artist/album ids for a track that arrived without them. Wired by the app.
    @ObservationIgnored var linkResolver: ((String) async throws -> TrackLinks?)?
    @ObservationIgnored private var resolvingLinksFor: String?

    /// True between asking the web view to load a track and seeing state for that track.
    private var isLoading = false
    /// Nudge playback once if the page loads paused (YouTube occasionally waits for a gesture).
    private var wantsAutoplayNudge = false
    /// After an optimistic play/pause, ignore the web view's stale `isPlaying` until this time.
    private var trustWebPlayStateAfter: Date = .distantPast
    /// The restored queue hasn't been loaded into the web view yet; the first play does that.
    private var needsLoad = false
    /// Position to seek to once the restored track is playing.
    private var pendingSeek: Double?
    private var lastSavedTime: Double = 0

    private static let savedKey = "playbackState"
    private struct Saved: Codable {
        var queue: [Track]
        var index: Int?
        var time: Double
    }

    init(auth: AuthService) {
        bridge = PlayerBridge(dataStore: auth.dataStore)
        bridge.onEvent = { [weak self] event in self?.handle(event) }
        restore()
    }

    // MARK: Commands

    /// Preload the YouTube Music shell so the first play is an in-app navigation.
    func warmUp() {
        bridge.warmUp()
    }

    func play(_ tracks: [Track], startingAt index: Int) {
        guard tracks.indices.contains(index) else { return }
        queue = tracks
        load(index: index)
    }

    func togglePlayPause() {
        isPlaying ? pause() : resume()
    }

    func resume() {
        guard let index = currentIndex, current != nil else { return }
        if needsLoad {
            pendingSeek = currentTime > 1 ? currentTime : nil
            load(index: index)
            return
        }
        setPlayingOptimistically(true)
        bridge.play()
    }

    func pause() {
        guard current != nil else { return }
        setPlayingOptimistically(false)
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
        save()
    }

    // MARK: Persistence

    private func save() {
        lastSavedTime = currentTime
        let saved = Saved(queue: queue, index: currentIndex, time: currentTime)
        UserDefaults.standard.set(try? JSONEncoder().encode(saved), forKey: Self.savedKey)
    }

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: Self.savedKey),
              let saved = try? JSONDecoder().decode(Saved.self, from: data),
              let index = saved.index, saved.queue.indices.contains(index) else { return }
        queue = saved.queue
        currentIndex = index
        currentTime = saved.time
        needsLoad = true
    }

    // MARK: Internals

    private func load(index: Int) {
        currentIndex = index
        needsLoad = false
        resetLiveState()
        // Switching tracks is still "playing" as far as the listener is concerned; don't let the
        // button flip to play while the next track spins up.
        isPlaying = true
        trustWebPlayStateAfter = .now.addingTimeInterval(1.5)
        isLoading = true
        wantsAutoplayNudge = true
        bridge.load(videoId: queue[index].id)
        save()
    }

    private func setPlayingOptimistically(_ playing: Bool) {
        isPlaying = playing
        trustWebPlayStateAfter = .now.addingTimeInterval(0.6)
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
        case .remote(.next):
            next()
        case .remote(.previous):
            previous()
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
            // Stale state from the previous document while a load is in flight, or YouTube's own
            // restored player while we still hold a restored queue of our own.
            if isLoading || needsLoad { return }
            adopt(videoId: videoId, from: s)
        }
        isLoading = false
        if s.isPlaying == isPlaying || Date.now >= trustWebPlayStateAfter {
            isPlaying = s.isPlaying
        }
        if let target = pendingSeek, s.isPlaying {
            pendingSeek = nil
            bridge.seek(to: target)
            return
        }
        currentTime = s.currentTime
        if abs(currentTime - lastSavedTime) > 5 { save() }
        duration = s.duration
        liveTitle = s.title
        liveArtist = s.artist
        liveArtworkURL = s.artworkURL ?? liveArtworkURL
        fillLinks(from: s)
        resolveLinksIfNeeded()

        if wantsAutoplayNudge {
            if s.isPlaying {
                wantsAutoplayNudge = false
            } else if s.duration > 0 {
                wantsAutoplayNudge = false
                bridge.play()
            }
        }
    }

    /// Tracks from the home feed or YouTube's own continuation arrive without artist/album ids;
    /// the web player's byline has them, so backfill the current track once they show up.
    private func fillLinks(from s: PlaybackSnapshot) {
        guard let i = currentIndex, queue.indices.contains(i) else { return }
        var track = queue[i]
        var changed = false
        if track.artistId == nil, let artistId = s.artistId {
            track.artistId = artistId
            changed = true
        }
        if track.albumId == nil, let albumId = s.albumId {
            track.albumId = albumId
            if track.album == nil { track.album = s.albumTitle }
            changed = true
        }
        guard changed else { return }
        queue[i] = track
        save()
    }

    /// The DOM doesn't always link the byline, so ask InnerTube once per track for what's missing.
    private func resolveLinksIfNeeded() {
        guard let track = current, track.artistId == nil || track.albumId == nil,
              resolvingLinksFor != track.id, let linkResolver else { return }
        resolvingLinksFor = track.id
        Task { [weak self] in
            guard let links = try? await linkResolver(track.id), let self else { return }
            guard let i = self.currentIndex, self.queue.indices.contains(i), self.queue[i].id == track.id else { return }
            var updated = self.queue[i]
            if updated.artistId == nil, let artistId = links.artistId {
                updated.artistId = artistId
                if updated.artist.isEmpty, let artist = links.artist { updated.artist = artist }
            }
            if updated.albumId == nil, let albumId = links.albumId {
                updated.albumId = albumId
                if updated.album == nil { updated.album = links.album }
            }
            guard updated != self.queue[i] else { return }
            self.queue[i] = updated
            self.save()
        }
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
        save()
    }
}
