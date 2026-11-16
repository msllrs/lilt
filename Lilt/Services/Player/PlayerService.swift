import Foundation
import Observation
import WebKit

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
    /// Whether the playing track is liked on YouTube Music, as the page reports it.
    private(set) var isLiked = false

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

    /// The web player you hear.
    @ObservationIgnored private(set) var bridge: any PlayerBridging
    /// Makes a web player (a real one signed in on the app's data store, or a test's fake).
    @ObservationIgnored private let makeBridge: @MainActor () -> any PlayerBridging
    /// Puts a web player's view in a window, where it has to be to keep playing. Wired by the app.
    @ObservationIgnored var hostWebView: ((WKWebView) -> Void)? {
        didSet { for view in [bridge.webView, standby?.webView].compactMap({ $0 }) { hostWebView?(view) } }
    }

    // MARK: Gapless state

    static let gaplessKey = "gaplessPlayback"
    /// Where Settings ▸ Playback's gapless picker kept its mode, for a while; `storedGapless`
    /// moves it onto `gaplessKey` and removes it.
    static let legacyGaplessModeKey = "gaplessMode"

    /// The stored switch, on when nothing is stored. A mode left by the old picker is moved onto
    /// it first: off stays off, and any other (YouTube's own queue, Chrome mode or the second
    /// player) is on, the second player being all that's left of them.
    static func storedGapless(_ defaults: UserDefaults = .standard) -> Bool {
        if let mode = defaults.string(forKey: legacyGaplessModeKey) {
            defaults.set(mode != "off", forKey: gaplessKey)
            defaults.removeObject(forKey: legacyGaplessModeKey)
        }
        return defaults.object(forKey: gaplessKey) as? Bool ?? true
    }

    /// Gapless playback: a second web player, signed in on the same data store, holds the song
    /// that plays next muted and paused at 0:00, and takes over the instant the current one
    /// ends. Off, there is one web player and every change is a load, exactly as before.
    var isGapless = PlayerService.storedGapless() {
        didSet {
            UserDefaults.standard.set(isGapless, forKey: Self.gaplessKey)
            syncStandby()
        }
    }
    /// The web player waiting with the next song; nil with gapless off or before the first play.
    @ObservationIgnored private(set) var standby: (any PlayerBridging)?
    /// The song the standby is cueing or holding, and whether it's buffered and ready to start.
    @ObservationIgnored private(set) var standbyTrackId: String?
    @ObservationIgnored private(set) var isStandbyReady = false
    /// A song the standby couldn't cue; it isn't tried again until another song has started.
    @ObservationIgnored private var failedCue: String?
    /// Whether the last change of song was a handover rather than a load (for the gap log).
    @ObservationIgnored private var handedOver = false
    /// After a handover, the song that should be heard within `handoverTimeout`; if it isn't,
    /// it's loaded the ordinary way.
    @ObservationIgnored private var awaitingSound: String?
    @ObservationIgnored private var handoverWatch: Task<Void, Never>?
    @ObservationIgnored var handoverTimeout: Duration = .seconds(3)
    /// "web player 1", "web player 2", in the order they were made, for the gapless trace.
    @ObservationIgnored private var bridgeNames: [ObjectIdentifier: String] = [:]
    /// Looks up artist/album ids for a track that arrived without them. Wired by the app.
    @ObservationIgnored var linkResolver: ((String) async throws -> TrackLinks?)?
    /// Reports each like the player makes, so rows elsewhere agree. Wired by the app.
    @ObservationIgnored var onLikeToggled: (@MainActor (Track, Bool) -> Void)?
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
    /// The web view has a live playback session for the current track, so WebKit holds the
    /// system Now Playing entry and receives the media keys. False after a relaunch until the
    /// restored track is actually loaded; `RemoteCommandBridge` covers that window.
    private(set) var hasWebSession = false
    /// The system paused a playing song (AirPods taken out, say) and nothing has been done by
    /// hand since, so the system's Play when they go back in should resume it.
    ///
    /// macOS sends one Pause per AirPod taken out. With both out the second finds Lilt already
    /// paused, and from then on macOS doesn't count Lilt's web session among the players it
    /// paused: its Play goes only to apps listening in their own process. So this keeps the
    /// first Pause's word through the second, and `RemoteCommandBridge` listens for that Play
    /// in Lilt's own process while it's set.
    private(set) var isPausedRemotely = false
    /// Position to seek to once the restored track is playing.
    private var pendingSeek: Double?
    private var lastSavedTime: Double = 0
    /// The automatic track change being timed (DEBUG logs it): from the old track's `ended` to
    /// the new one's first `playing`, which is the silence the listener hears between them.
    @ObservationIgnored private var gap: GapTrace?
    private struct GapTrace {
        let old: Track
        let new: Track
        let mode: String
        let endedAt: Date
    }

    private static let savedKey = "playbackState"
    private struct Saved: Codable {
        var queue: [Track]
        var index: Int?
        var time: Double
        var isShuffled: Bool?
        var unshuffledQueue: [Track]?
        var repeatMode: RepeatMode?
        var manualCount: Int?
        var sourceId: String?
        var sourceTitle: String?
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

    init(auth: AuthService, makeBridge: (@MainActor () -> any PlayerBridging)? = nil) {
        let make = makeBridge ?? { [dataStore = auth.dataStore] in PlayerBridge(dataStore: dataStore) }
        self.makeBridge = make
        bridge = make()
        route(bridge)
        restore()
    }

    /// Only the web player you hear drives playback; the standby's state, ends and remote
    /// commands are about a song nobody is listening to.
    private func route(_ player: any PlayerBridging) {
        bridgeNames[ObjectIdentifier(player)] = "web player \(bridgeNames.count + 1)"
        (player as? PlayerBridge)?.logName = bridgeNames[ObjectIdentifier(player)] ?? "web player"
        player.onEvent = { [weak self, weak player] event in
            guard let self, let player else { return }
            self.traceArrival(of: event, from: player)
            if player === self.bridge {
                self.handle(event)
            } else if player === self.standby {
                self.handleStandby(event)
            }
        }
    }

    // MARK: Commands

    /// Preload the YouTube Music shell so the first play is an in-app navigation.
    func warmUp() {
        bridge.warmUp()
    }

    /// The browse id of the album or playlist the queue was started from, so only that page
    /// (and its row) shows as playing; a track played from anywhere else has no source, even
    /// if some playlist happens to contain it. It goes once YouTube Music carries on past the
    /// queue with a pick of its own.
    private(set) var sourceId: String?
    /// Its title, for the up-next list's "from" line.
    private(set) var sourceTitle: String?

    /// Plays `tracks` from `index` in their own order. Shuffle belongs to the list it was turned
    /// on for, so a new list starts with it off.
    /// Songs YouTube Music greys out are left out of the queue; `index` counts them, so the
    /// song asked for still plays, and asking for one of them plays nothing.
    func play(_ tracks: [Track], startingAt index: Int, source: BrowseItem? = nil) {
        guard tracks.indices.contains(index), tracks[index].isUnavailable != true else { return }
        let playable = tracks.filter { $0.isUnavailable != true }
        let skipped = tracks[..<index].count { $0.isUnavailable == true }
        start(playable, at: index - skipped, source: source, shuffled: false)
    }

    /// Starts `tracks` in a random order with shuffle on, leaving out the greyed-out ones.
    func playShuffled(_ tracks: [Track], source: BrowseItem? = nil) {
        let playable = tracks.filter { $0.isUnavailable != true }
        guard !playable.isEmpty else { return }
        start(playable, at: Int.random(in: playable.indices), source: source, shuffled: true)
    }

    /// Replaces the queue with `tracks` and plays the one at `index`, shuffling what follows it
    /// when asked to.
    private func start(_ tracks: [Track], at index: Int, source: BrowseItem?, shuffled: Bool) {
        guard tracks.indices.contains(index) else { return }
        sourceId = source?.id
        sourceTitle = source?.title
        queue = tracks
        unshuffledQueue = nil
        manualTokens = []
        isShuffled = shuffled
        if shuffled { shuffleRemainder(keeping: index) } else { load(index: index) }
    }

    /// Plays a mix from its first song, as `play` does, unless that song is the one playing (a
    /// mix started from the song you're listening to): then it plays on uninterrupted and the
    /// mix becomes what follows it, in place of the rest of the queue. Either way the mix plays
    /// in its own order, with shuffle off.
    func playMix(_ tracks: [Track], source: BrowseItem) {
        guard let first = tracks.first else { return }
        guard let current, current.id == first.id else {
            play(tracks, startingAt: 0, source: source)
            return
        }
        sourceId = source.id
        sourceTitle = source.title
        queue = [current] + tracks.dropFirst()
        currentIndex = 0
        unshuffledQueue = nil
        manualTokens = []
        isShuffled = false
        save()
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
        setRepeat(repeatMode.next)
    }

    func setRepeat(_ mode: RepeatMode) {
        repeatMode = mode
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

    /// Likes or unlikes the playing track through the page's own button. Flipped at once so the
    /// heart answers the click; the next state update confirms it.
    func toggleLike() {
        guard let current else { return }
        isLiked.toggle()
        onLikeToggled?(current, isLiked)
        bridge.toggleLike()
    }

    func togglePlayPause() {
        isPlaying ? pause() : resume()
    }

    func resume() {
        guard let index = currentIndex, current != nil else { return }
        isPausedRemotely = false
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
        isPausedRemotely = false
        setPlayingOptimistically(false)
        bridge.pause()
        save()
    }

    /// The system's Pause, forwarded by the page's media session. Only a pause of something
    /// playing is one to undo: a second Pause while already paused (the other AirPod) keeps the
    /// first one's mark, and one with nothing playing doesn't make one.
    private func pauseRemotely() {
        guard isPlaying else { return }
        pause()
        isPausedRemotely = true
    }

    /// The system's Play after its own pause: resumes, and says so, only when the pause it
    /// answers is still waiting, so a Play after you've paused by hand leaves the music be.
    @discardableResult
    func resumeAfterRemotePause() -> Bool {
        guard isPausedRemotely else { return false }
        resume()
        return true
    }

    /// Controls ▸ Sleep Timer: how long it was set for, while it runs. When the time is up the
    /// music pauses, whatever is playing by then, and the timer is spent. The app saves it
    /// (`SleepTimerStore`), so a relaunch before then still pauses on time.
    private(set) var sleepTimer: Duration?
    /// When a running timer pauses the music.
    private(set) var sleepEnds: Date?
    @ObservationIgnored private var sleepTask: Task<Void, Never>?

    /// Sets the timer running for `duration` from now, in place of any before it; nil turns it
    /// off. `remaining` runs a timer of that length already partly spent.
    func setSleepTimer(_ duration: Duration?, remaining: Duration? = nil) {
        sleepTask?.cancel()
        sleepTimer = duration
        guard let duration else { sleepEnds = nil; return }
        let wait = remaining ?? duration
        sleepEnds = Date.now.addingTimeInterval(Double(wait.components.seconds) + Double(wait.components.attoseconds) / 1e18)
        sleepTask = Task { [weak self] in
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled, let self else { return }
            sleepTimer = nil
            sleepEnds = nil
            trace("sleep timer paused the music")
            pause()
        }
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
        tearDownStandby()
        hasWebSession = false
        isPausedRemotely = false
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

    /// How many of the running list's own next tracks the up-next list shows after your adds.
    static let automaticShown = 10

    /// What follows your adds: the rest of the list you started from, in play order (the next
    /// `automaticShown` of them).
    var automaticUpcoming: [Track] {
        guard let i = currentIndex, queue.indices.contains(i) else { return [] }
        let start = min(queue.count, i + 1 + manualCount)
        let end = min(queue.count, start + Self.automaticShown)
        return start < end ? Array(queue[start..<end]) : []
    }

    /// Jumps to a track in `automaticUpcoming`. Your adds come along behind it (see
    /// `adjustManual`); the automatic tracks skipped over are dropped, as played.
    func playAutomatic(at offset: Int) {
        guard let i = currentIndex else { return }
        let start = i + 1 + manualCount
        guard queue.indices.contains(start + offset) else { return }
        queue.removeSubrange(start..<(start + offset))
        load(index: start)
    }

    /// Adds a track to the end of what's queued by hand, ahead of the rest of the list (as many
    /// times as you like); with nothing playing, it starts a queue of its own. Returns the new
    /// entry's identity, or nil when it started playing instead.
    @discardableResult
    func enqueue(_ track: Track) -> UUID? {
        guard let i = currentIndex, current != nil else {
            play([track], startingAt: 0)
            return nil
        }
        let at = min(queue.count, i + 1 + manualCount)
        queue.insert(track, at: at)
        if unshuffledQueue != nil, let j = unshuffledQueue!.firstIndex(where: { $0.id == queue[i].id }) {
            unshuffledQueue!.insert(track, at: min(unshuffledQueue!.count, j + 1 + manualCount))
        }
        let token = UUID()
        manualTokens.append(token)
        save()
        return token
    }

    /// Puts tracks straight after the current one, in order, ahead of anything already queued by
    /// hand; with nothing playing, they start a queue of their own. Returns the new entries'
    /// identities, none when they started playing instead.
    @discardableResult
    func playNext(_ tracks: [Track]) -> [UUID] {
        let tracks = tracks.filter { $0.isUnavailable != true }
        guard !tracks.isEmpty else { return [] }
        guard let i = currentIndex, current != nil else {
            play(tracks, startingAt: 0)
            return []
        }
        queue.insert(contentsOf: tracks, at: min(queue.count, i + 1))
        if unshuffledQueue != nil, let j = unshuffledQueue!.firstIndex(where: { $0.id == queue[i].id }) {
            unshuffledQueue!.insert(contentsOf: tracks, at: min(unshuffledQueue!.count, j + 1))
        }
        let tokens = tracks.map { _ in UUID() }
        manualTokens.insert(contentsOf: tokens, at: 0)
        save()
        return tokens
    }

    /// Removes the track at an offset into `upcoming`.
    func removeUpcoming(at offset: Int) {
        guard let i = currentIndex, offset < manualCount, queue.indices.contains(i + 1 + offset) else { return }
        let removed = queue.remove(at: i + 1 + offset)
        if let j = unshuffledQueue?.lastIndex(where: { $0.id == removed.id }) { unshuffledQueue?.remove(at: j) }
        manualTokens.remove(at: offset)
        save()
    }

    /// Removes these entries from `upcoming`, wherever they've got to; other copies of the same
    /// song stay. Entries already played or gone are skipped.
    func removeUpcoming(ids: [UUID]) {
        for id in ids {
            if let offset = upcomingOffset(of: id) { removeUpcoming(at: offset) }
        }
    }

    /// Puts a track back into `upcoming` at an offset (clamped to what's there), as a new entry.
    /// Nil when nothing is playing to queue it behind.
    @discardableResult
    func insertUpcoming(_ track: Track, at offset: Int) -> UUID? {
        guard let i = currentIndex, current != nil else { return nil }
        let offset = min(max(offset, 0), manualCount)
        queue.insert(track, at: min(queue.count, i + 1 + offset))
        if unshuffledQueue != nil, let j = unshuffledQueue!.firstIndex(where: { $0.id == queue[i].id }) {
            unshuffledQueue!.insert(track, at: min(unshuffledQueue!.count, j + 1 + offset))
        }
        let token = UUID()
        manualTokens.insert(token, at: offset)
        save()
        return token
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
            manualCount: manualCount, sourceId: sourceId, sourceTitle: sourceTitle
        )
        UserDefaults.standard.set(try? JSONEncoder().encode(saved), forKey: Self.savedKey)
        // Every change to the queue, its order or its repeat lands here, so this is where the
        // standby learns what plays next.
        syncStandby()
    }

    /// Takes up the saved queue and playhead, ready to load. Internal so tests can put the app's
    /// own player on a queue of their choosing and back again.
    func restore() {
        guard let data = UserDefaults.standard.data(forKey: Self.savedKey),
              let saved = try? JSONDecoder().decode(Saved.self, from: data),
              let index = saved.index, saved.queue.indices.contains(index) else { return }
        queue = saved.queue
        currentIndex = index
        currentTime = saved.time
        isShuffled = saved.isShuffled ?? false
        unshuffledQueue = saved.unshuffledQueue
        repeatMode = saved.repeatMode ?? .off
        sourceId = saved.sourceId
        sourceTitle = saved.sourceTitle
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
        // Another song, or the same one again, by hand or by the queue: whatever the system
        // paused has been moved on from.
        isPausedRemotely = false
        gap = nil
        failedCue = nil
        awaitingSound = nil
        handoverWatch?.cancel()
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
        handedOver = canHandOver(to: queue[index].id)
        if handedOver {
            handOver()
        } else {
            trace("fallback load \(queue[index].id) on \(describe(bridge)): \(whyNotHandedOver(to: queue[index].id))")
            bridge.load(videoId: queue[index].id)
        }
        recents?.recordPlayed(queue[index], artwork: liveArtworkURL)
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
        case .remote(.pause):
            pauseRemotely()
        case .remote(.play):
            resume()
        case .ended(let videoId):
            guard videoId == current?.id, let i = currentIndex else { return }
            let old = queue[i]
            if repeatMode == .one {
                load(index: i)
            } else if hasNext {
                next()
            } else {
                // Let YouTube Music continue with its own pick; `adopt` picks it up.
                isLoading = false
                return
            }
            if let new = current { gap = GapTrace(old: old, new: new, mode: handedOver ? "handover" : "single", endedAt: .now) }
        case .playing(let videoId):
            if videoId == awaitingSound {
                awaitingSound = nil
                handoverWatch?.cancel()
            }
            guard let trace = gap, videoId == trace.new.id else {
                self.trace("gap trace " + (gap.map { "waits for \($0.new.id), not \(videoId ?? "nil")" } ?? "none running for \(videoId ?? "nil")"))
                return
            }
            self.trace("gap trace matched \(trace.new.id)")
            gap = nil
            #if DEBUG
            let ms = Int((Date.now.timeIntervalSince(trace.endedAt) * 1000).rounded())
            DebugLog.player("Lilt gap \(ms)ms \(trace.old.title)→\(trace.new.title) (\(trace.mode))")
            #endif
        case .state(let s):
            apply(s)
        case .playbackError(let videoId, let reason):
            trace("playback error on \(describe(bridge)) for \(videoId ?? "nil"): \(reason)")
        case .cued, .cueFailed:
            break
        }
    }

    // MARK: Gapless playback

    /// The song that plays when the current one ends by itself, as `handle(.ended)` picks it;
    /// nil when YouTube Music's own continuation takes over.
    var followingTrack: Track? {
        guard let i = currentIndex, queue.indices.contains(i) else { return nil }
        if repeatMode == .one { return queue[i] }
        if i + 1 < queue.count { return queue[i + 1] }
        return repeatMode == .all ? queue.first : nil
    }

    /// Points the standby at `followingTrack`, re-cueing only when that changed. It waits until
    /// the current song is under way (its first report is in), so the two don't fight for the
    /// network, and it isn't created at all until something has played.
    private func syncStandby() {
        guard isGapless else { tearDownStandby(); return }
        guard current != nil else { parkStandby(); return }
        guard !needsLoad, !isLoading else { return }
        guard let next = followingTrack, next.id != failedCue else { parkStandby(); return }
        guard next.id != standbyTrackId else { return }
        let standby = self.standby ?? makeStandby()
        standbyTrackId = next.id
        isStandbyReady = false
        trace("standby cue requested: \(next.id) on \(describe(standby))")
        standby.cue(videoId: next.id)
    }

    private func makeStandby() -> any PlayerBridging {
        let player = makeBridge()
        route(player)
        standby = player
        if let view = player.webView { hostWebView?(view) }
        return player
    }

    /// Nothing to hold: keep the page (and its signed-in shell) but silent.
    private func parkStandby() {
        guard standbyTrackId != nil else { return }
        standbyTrackId = nil
        isStandbyReady = false
        standby?.hold()
    }

    private func tearDownStandby() {
        guard let standby else { return }
        standby.onEvent = nil
        standby.unload()
        standby.webView?.removeFromSuperview()
        self.standby = nil
        standbyTrackId = nil
        isStandbyReady = false
    }

    private func handleStandby(_ event: PlayerEvent) {
        switch event {
        case .cued(let videoId):
            guard videoId == standbyTrackId else { return }
            isStandbyReady = true
        case .cueFailed(let videoId):
            guard videoId == standbyTrackId else { return }
            failedCue = videoId
            standbyTrackId = nil
            isStandbyReady = false
        default:
            break
        }
    }

    /// A resumed position can't be handed over: the standby waits at 0:00.
    private func canHandOver(to videoId: String) -> Bool {
        isGapless && standby != nil && isStandbyReady && standbyTrackId == videoId && pendingSeek == nil
    }

    /// The standby starts its song and becomes the player you hear; the old one is silenced
    /// (it has ended, or you skipped it) and waits for whatever follows.
    private func handOver() {
        guard let next = standby else { return }
        trace("handover started: \(current?.id ?? "nil") on \(describe(next)), \(describe(bridge)) held")
        let old = bridge
        bridge = next
        standby = old
        standbyTrackId = nil
        isStandbyReady = false
        next.start()
        old.hold()
        guard let id = current?.id else { return }
        awaitingSound = id
        handoverWatch = Task { [weak self, timeout = handoverTimeout] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled, let self, self.awaitingSound == id, self.current?.id == id else { return }
            // It never sounded (YouTube paused it, or the page lost its video): load it the
            // ordinary way on the same page.
            self.awaitingSound = nil
            self.trace("fallback load \(id) on \(self.describe(self.bridge)): the handover made no sound within \(timeout)")
            self.bridge.load(videoId: id)
        }
    }

    // MARK: Gapless trace (DEBUG)

    /// One line per step of a handover (and each playback error), in the diagnostics log, to
    /// see in the running app where one stops; debug builds keep the `Lilt gapless: …` line too.
    private func trace(_ message: @autoclosure () -> String) {
        let line = message()
        Diagnostics.shared.record(.player, line)
        #if DEBUG
        DebugLog.player("Lilt gapless: " + line)
        #endif
    }

    /// The web player's name and whether it's the one you hear.
    private func describe(_ player: (any PlayerBridging)?) -> String {
        guard let player else { return "no web player" }
        let name = bridgeNames[ObjectIdentifier(player)] ?? "web player ?"
        let role = player === bridge ? "active" : player === standby ? "standby" : "detached"
        return "\(name) (\(role))"
    }

    /// Events from either web player as they arrive, before anything filters them.
    private func traceArrival(of event: PlayerEvent, from player: any PlayerBridging) {
        switch event {
        case .ended(let id):
            trace("TRACK_ENDED from \(describe(player)): \(id ?? "nil"), current \(current?.id ?? "nil")" + (id == current?.id ? "" : " (mismatch)"))
        case .playing(let id):
            trace("PLAYING from \(describe(player)): \(id ?? "nil"), current \(current?.id ?? "nil")")
        case .cued(let id):
            trace("CUED from \(describe(player)): \(id), standby holds \(standbyTrackId ?? "nil")")
        case .cueFailed(let id):
            trace("CUE_FAILED from \(describe(player)): \(id), standby holds \(standbyTrackId ?? "nil")")
        default:
            break
        }
    }

    /// Which of `canHandOver`'s conditions failed.
    private func whyNotHandedOver(to videoId: String) -> String {
        if !isGapless { return "gapless is off" }
        guard standby != nil else { return "no standby yet" }
        if pendingSeek != nil { return "resuming partway through" }
        if standbyTrackId != videoId { return "standby holds \(standbyTrackId ?? "nothing"), not \(videoId)" }
        if !isStandbyReady { return "standby still cueing \(videoId)" }
        return "unknown"
    }

    private func apply(_ s: PlaybackSnapshot) {
        guard let videoId = s.videoId else { return }
        if videoId != current?.id {
            // Stale state from the previous document while a load is in flight.
            if isLoading { return }
            // YouTube's own restored player while we still hold a restored queue of our own: a
            // paused one is ignored (ours wins when you press play), but one that is actually
            // playing is what you're hearing, so the platter follows it from then on.
            if needsLoad {
                guard s.isPlaying else { return }
                needsLoad = false
            }
            adopt(videoId: videoId, from: s)
        }
        if isLoading {
            isLoading = false
            syncStandby()
        }
        // WebKit only registers with Now Playing once the page actually plays. A snapshot of
        // YouTube's own restored (paused) player after a relaunch doesn't count, so the bridge
        // keeps Lilt's entry until our restored track is loaded and running.
        if !needsLoad, s.isPlaying { hasWebSession = true }
        if s.isPlaying == isPlaying || Date.now >= trustWebPlayStateAfter {
            isPlaying = s.isPlaying
        }
        // Playing again by some way of the page's own: there's no longer a pause to undo.
        if isPlaying { isPausedRemotely = false }
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
        if let status = s.likeStatus { isLiked = status == "LIKE" }
        if let current { recents?.updateArtwork(forPlayed: current.id, url: liveArtworkURL) }
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
    /// the UI follows along. The queue has left its album or playlist, so that's no longer the source.
    private func adopt(videoId: String, from s: PlaybackSnapshot) {
        sourceId = nil
        sourceTitle = nil
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
