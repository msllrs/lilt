import Foundation
import Observation

/// Playback state and queue. Lilt's queue is the source of truth: next/previous navigate the
/// hidden web view explicitly rather than trusting YouTube Music's own autoplay.
@MainActor
@Observable
final class PlayerService {
    enum RepeatMode: String, Codable {
        case off, all, one

        var next: RepeatMode {
            switch self {
            case .off: .all
            case .all: .one
            case .one: .off
            }
        }
    }

    private(set) var queue: [Track] = []
    private(set) var currentIndex: Int?
    private(set) var isPlaying = false
    private(set) var isShuffled = false
    private(set) var repeatMode: RepeatMode = .off
    /// The queue's order before shuffling, so turning shuffle off restores it.
    private var unshuffledQueue: [Track]?
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
    var hasNext: Bool {
        guard let i = currentIndex else { return false }
        return i + 1 < queue.count || (repeatMode != .off && !queue.isEmpty)
    }
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
    /// Receives every track that starts, for the recents menu. Wired by the app.
    @ObservationIgnored weak var recents: RecentsStore?
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
        var isShuffled: Bool?
        var unshuffledQueue: [Track]?
        var repeatMode: RepeatMode?
        var manualCount: Int?
    }

    /// One token per track put right after the current one by hand ("up next"). They play
    /// before the rest of whatever list is running, and they're all the queue view shows. The
    /// tokens give each entry a stable identity even when the same track is queued twice, so
    /// rows can animate in, out and around.
    private var manualTokens: [UUID] = []
    var manualCount: Int { manualTokens.count }

    struct QueuedEntry: Identifiable, Equatable {
        let id: UUID
        let track: Track
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
        unshuffledQueue = nil
        manualTokens = []
        if isShuffled { shuffleRemainder(keeping: index) } else { load(index: index) }
    }

    /// Shuffle what's left after the current track; off restores the original order.
    func toggleShuffle() {
        isShuffled.toggle()
        guard let i = currentIndex, queue.indices.contains(i) else { save(); return }
        if isShuffled {
            shuffleRemainder(keeping: i, reload: false)
        } else if let original = unshuffledQueue {
            let currentId = queue[i].id
            let manual = upcoming
            queue = original
            currentIndex = original.firstIndex { $0.id == currentId } ?? i
            unshuffledQueue = nil
            // The hand-placed tracks stay right behind the current one in the restored order.
            for track in manual { if let j = queue.lastIndex(where: { $0.id == track.id }) { queue.remove(at: j) } }
            queue.insert(contentsOf: manual, at: min(currentIndex! + 1, queue.count))
        }
        save()
    }

    func cycleRepeat() {
        repeatMode = repeatMode.next
        save()
    }

    /// Keeps the chosen track (and anything queued by hand behind it) in place and shuffles
    /// everything after.
    private func shuffleRemainder(keeping index: Int, reload: Bool = true) {
        unshuffledQueue = unshuffledQueue ?? queue
        let current = queue[index]
        let manualEnd = min(queue.count, index + 1 + manualCount)
        let manual = Array(queue[(index + 1)..<manualEnd])
        var rest = queue
        rest.removeSubrange(index..<manualEnd)
        rest.shuffle()
        queue = [current] + manual + rest
        if reload { load(index: 0, keepingManual: true) } else { currentIndex = 0 }
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
        save()
    }

    /// Flush the queue and playhead to disk (called when the app is about to quit).
    func persistNow() {
        save()
    }

    func next() {
        guard let i = currentIndex else { return }
        if i + 1 < queue.count {
            load(index: i + 1)
        } else if repeatMode != .off, !queue.isEmpty {
            load(index: 0)
        }
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

    // MARK: Up next

    /// The tracks queued by hand, in play order (the rest of the running list isn't shown).
    var upcoming: [Track] {
        guard let i = currentIndex, queue.indices.contains(i) else { return [] }
        let end = min(queue.count, i + 1 + manualCount)
        return i + 1 < end ? Array(queue[(i + 1)..<end]) : []
    }

    /// `upcoming` with each entry's stable identity.
    var upcomingEntries: [QueuedEntry] {
        zip(manualTokens, upcoming).map { QueuedEntry(id: $0, track: $1) }
    }

    func upcomingOffset(of id: UUID) -> Int? { manualTokens.firstIndex(of: id) }

    /// Adds a track to the end of what's queued by hand, ahead of the rest of the list (as many
    /// times as you like); with nothing playing, it starts a queue of its own.
    func enqueue(_ track: Track) {
        guard let i = currentIndex, current != nil else {
            play([track], startingAt: 0)
            return
        }
        let at = min(queue.count, i + 1 + manualCount)
        queue.insert(track, at: at)
        if unshuffledQueue != nil, let j = unshuffledQueue!.firstIndex(where: { $0.id == queue[i].id }) {
            unshuffledQueue!.insert(track, at: min(unshuffledQueue!.count, j + 1 + manualCount))
        }
        manualTokens.append(UUID())
        save()
    }

    /// Removes the track at an offset into `upcoming`.
    func removeUpcoming(at offset: Int) {
        guard let i = currentIndex, offset < manualCount, queue.indices.contains(i + 1 + offset) else { return }
        let removed = queue.remove(at: i + 1 + offset)
        if let j = unshuffledQueue?.lastIndex(where: { $0.id == removed.id }) { unshuffledQueue?.remove(at: j) }
        manualTokens.remove(at: offset)
        save()
    }

    /// Reorders `upcoming` the way `ForEach.onMove` reports it.
    func moveUpcoming(from source: IndexSet, to destination: Int) {
        guard let i = currentIndex, manualCount > 0 else { return }
        var segment = upcoming
        segment.move(fromOffsets: source, toOffset: destination)
        manualTokens.move(fromOffsets: source, toOffset: destination)
        queue.replaceSubrange((i + 1)..<(i + 1 + segment.count), with: segment)
        save()
    }

    /// Jumps to a track in `upcoming`; the ones skipped over are dropped, as played.
    func playUpcoming(at offset: Int) {
        guard let i = currentIndex, offset < manualCount, queue.indices.contains(i + 1 + offset) else { return }
        queue.removeSubrange((i + 1)..<(i + 1 + offset))
        manualTokens.removeFirst(offset)
        load(index: i + 1)
    }

    /// Keeps the hand-queued tracks adjacent to whatever is current. Stepping into the segment
    /// consumes one; jumping anywhere else carries the segment along behind the new track.
    private func adjustManual(for newIndex: Int) {
        guard let old = currentIndex, manualCount > 0, queue.indices.contains(old) else { return }
        if newIndex == old + 1 {
            manualTokens.removeFirst()
            return
        }
        let end = min(queue.count, old + 1 + manualCount)
        let segment = Array(queue[(old + 1)..<end])
        queue.removeSubrange((old + 1)..<end)
        let target = newIndex > old ? newIndex - segment.count : newIndex
        queue.insert(contentsOf: segment, at: min(queue.count, target + 1))
        pendingLoadIndex = target
    }
    private var pendingLoadIndex: Int?

    // MARK: Persistence

    private func save() {
        lastSavedTime = currentTime
        let saved = Saved(
            queue: queue, index: currentIndex, time: currentTime,
            isShuffled: isShuffled, unshuffledQueue: unshuffledQueue, repeatMode: repeatMode,
            manualCount: manualCount
        )
        UserDefaults.standard.set(try? JSONEncoder().encode(saved), forKey: Self.savedKey)
    }

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: Self.savedKey),
              let saved = try? JSONDecoder().decode(Saved.self, from: data),
              let index = saved.index, saved.queue.indices.contains(index) else { return }
        queue = saved.queue
        currentIndex = index
        currentTime = saved.time
        isShuffled = saved.isShuffled ?? false
        unshuffledQueue = saved.unshuffledQueue
        repeatMode = saved.repeatMode ?? .off
        let manual = min(saved.manualCount ?? 0, max(0, saved.queue.count - index - 1))
        manualTokens = (0..<manual).map { _ in UUID() }
        needsLoad = true
    }

    // MARK: Internals

    private func load(index: Int, keepingManual: Bool = false) {
        var index = index
        if !keepingManual {
            adjustManual(for: index)
            if let moved = pendingLoadIndex { index = moved; pendingLoadIndex = nil }
        }
        currentIndex = index
        needsLoad = false
        let resumeAt = pendingSeek
        resetLiveState()
        // Resuming a restored track: keep the saved position on screen instead of dipping to
        // 0:00 until the seek lands.
        if let resumeAt { currentTime = resumeAt }
        // Switching tracks is still "playing" as far as the listener is concerned; don't let the
        // button flip to play while the next track spins up.
        isPlaying = true
        trustWebPlayStateAfter = .now.addingTimeInterval(1.5)
        isLoading = true
        wantsAutoplayNudge = true
        bridge.load(videoId: queue[index].id)
        recents?.recordPlayed(queue[index])
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
            guard videoId == current?.id, let i = currentIndex else { return }
            if repeatMode == .one {
                load(index: i)
            } else if hasNext {
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
