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
    /// The first duration the page reported for this song. In one continuous stream (YouTube's
    /// own gapless, where the browser supports it) `duration` grows as the next song is
    /// appended, so this is what the song's end is measured against.
    @ObservationIgnored private var songDuration: Double = 0

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

    /// How one song runs into the next when it ends by itself.
    enum GaplessMode: String, CaseIterable, Identifiable {
        /// Every change is a load, on one web player.
        case off
        /// YouTube Music's own Up Next queue is kept holding the song that plays next, and the
        /// page's player moves on to it by itself; Lilt follows along instead of loading it.
        case nativeQueue
        /// A second web player holds the next song muted and paused at 0:00, and takes over.
        case secondPlayer
        /// Experimental: native queue, with the player page presenting Chrome's user agent so
        /// YouTube's player turns on its own gapless (the next song appended into the same
        /// stream). See `InnerTubeClient.chromeUserAgent`.
        case chromeQueue

        var id: Self { self }

        var title: String {
            switch self {
            case .off: "Off"
            case .nativeQueue: "YouTube's own (native queue)"
            case .secondPlayer: "Second player (pre-load)"
            case .chromeQueue: "YouTube's own (Chrome mode)"
            }
        }

        /// Whether the next song waits in YouTube Music's own Up Next and the page moves on to it.
        var usesNativeQueue: Bool { self == .nativeQueue || self == .chromeQueue }
    }

    static let gaplessModeKey = "gaplessMode"
    /// The switch this setting replaced; read once, so turning it off is kept.
    static let gaplessKey = "gaplessPlayback"

    /// The stored mode; before there was one, the old switch off means off and anything else
    /// the new default.
    static func storedGaplessMode(_ defaults: UserDefaults = .standard) -> GaplessMode {
        if let raw = defaults.string(forKey: gaplessModeKey), let mode = GaplessMode(rawValue: raw) { return mode }
        if defaults.object(forKey: gaplessKey) as? Bool == false { return .off }
        return .nativeQueue
    }

    var gaplessMode: GaplessMode = PlayerService.storedGaplessMode() {
        didSet {
            UserDefaults.standard.set(gaplessMode.rawValue, forKey: Self.gaplessModeKey)
            guard gaplessMode != oldValue else { return }
            let userAgentChanged = bridgeUserAgent != playerUserAgent
            if gaplessMode == .chromeQueue, isChromeModeSuspended {
                trace("chrome mode stays off for this session after repeated playback errors; the player page keeps the Safari user agent")
            }
            if userAgentChanged {
                trace("player page user agent: \(userAgentName) for \(gaplessMode.rawValue), the page reloads")
                bridge.setUserAgent(playerUserAgent)
                bridgeUserAgent = playerUserAgent
                chromeFailures = 0
            }
            syncStandby()
            let movedOn = !gaplessMode.usesNativeQueue
                && fallBackFromNativeAdvance("the gapless mode changed to \(gaplessMode.rawValue)")
            if userAgentChanged && !movedOn { reloadForUserAgent() }
            syncNativeQueue()
        }
    }

    /// Chrome mode gave up after repeated playback errors: the player page is back on Safari's
    /// user agent (still following YouTube's own queue) until Lilt quits.
    @ObservationIgnored private(set) var isChromeModeSuspended = false
    /// The user agent the player page should present: Chrome's only in Chrome mode, and only
    /// on that page; the standby (second player mode) and everything else keep Safari's.
    var playerUserAgent: String {
        gaplessMode == .chromeQueue && !isChromeModeSuspended ? InnerTubeClient.chromeUserAgent : InnerTubeClient.safariUserAgent
    }
    /// What the player page was last given.
    @ObservationIgnored private var bridgeUserAgent = InnerTubeClient.safariUserAgent
    private var isChromeActive: Bool { playerUserAgent == InnerTubeClient.chromeUserAgent }
    private var userAgentName: String { isChromeActive ? "Chrome" : "Safari" }
    /// Chrome mode: playback errors and songs that didn't start, in a row. One loads the song
    /// again the ordinary way; `chromeFailureLimit` puts the page back on Safari's user agent.
    @ObservationIgnored private(set) var chromeFailures = 0
    static let chromeFailureLimit = 2
    /// Chrome mode: the song loaded and not yet heard, and how long it gets before that counts
    /// as a failure (a fresh page load takes longer than the 3s an in-page move gets).
    @ObservationIgnored private var chromeAwaitingStart: String?
    @ObservationIgnored private var chromeStartWatch: Task<Void, Never>?
    @ObservationIgnored var chromeStartTimeout: Duration = .seconds(10)
    /// Where the current song starts on the `<video>`'s timeline. Zero, except after YouTube's
    /// own gapless appended it to the song before in the same stream.
    @ObservationIgnored private var streamOffset: Double = 0
    /// Second player mode: a second web player, signed in on the same data store, holds the
    /// song that plays next muted and paused at 0:00, and takes over the instant the current one
    /// ends. Nil in any other mode, or before the first play.
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
    /// Native queue mode: the song YouTube Music's own Up Next was asked to hold straight after
    /// `nativeSource` (the song playing then), and whether the page's queue read it back there.
    @ObservationIgnored private(set) var nativeTarget: String?
    @ObservationIgnored private(set) var isNativeQueued = false
    @ObservationIgnored private var nativeSource: String?
    /// Failed attempts per "source>target"; a pair is left alone after `nativeAttempts`.
    @ObservationIgnored private var nativeFailures: [String: Int] = [:]
    static let nativeAttempts = 3
    /// After the song ended by itself with the next one queued natively: the move the page's
    /// player should be making on its own. Lilt follows it once it's seen, or loads the song the
    /// ordinary way after `nativeAdvanceTimeout`, or at once if the page moves elsewhere.
    @ObservationIgnored private(set) var nativeAdvance: NativeAdvance?
    @ObservationIgnored private var nativeWatch: Task<Void, Never>?
    @ObservationIgnored var nativeAdvanceTimeout: Duration = .seconds(3)
    struct NativeAdvance {
        let id = UUID()
        let from: Track
        let targetId: String
        /// When the old song stopped sounding; nil when the page went straight on without an
        /// `ended` (one continuous stream).
        let endedAt: Date?
        /// Set when the move was seen as the same `<video>` playing on past the old song's end.
        var continuation: Continuation?
    }
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
        bridge.setUserAgent(playerUserAgent)
        bridgeUserAgent = playerUserAgent
    }

    /// Only the web player you hear drives playback; the standby's state, ends and remote
    /// commands are about a song nobody is listening to.
    private func route(_ player: any PlayerBridging) {
        bridgeNames[ObjectIdentifier(player)] = "web player \(bridgeNames.count + 1)"
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
    /// if some playlist happens to contain it.
    private(set) var sourceId: String?
    /// Its title, for the up-next list's "from" line.
    private(set) var sourceTitle: String?

    func play(_ tracks: [Track], startingAt index: Int, source: BrowseItem? = nil) {
        guard tracks.indices.contains(index) else { return }
        sourceId = source?.id
        sourceTitle = source?.title
        queue = tracks
        unshuffledQueue = nil
        manualTokens = []
        if isShuffled { shuffleRemainder(keeping: index) } else { load(index: index) }
    }

    /// Starts `tracks` in a random order with shuffle on.
    func playShuffled(_ tracks: [Track], source: BrowseItem? = nil) {
        guard !tracks.isEmpty else { return }
        isShuffled = true
        play(tracks, startingAt: Int.random(in: tracks.indices), source: source)
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
        endChromeStartWatch()
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
        tearDownStandby()
        clearNativeQueue()
        endChromeStartWatch()
        hasWebSession = false
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

    /// Puts tracks straight after the current one, in order, ahead of anything already queued by
    /// hand; with nothing playing, they start a queue of their own.
    func playNext(_ tracks: [Track]) {
        guard !tracks.isEmpty else { return }
        guard let i = currentIndex, current != nil else {
            play(tracks, startingAt: 0)
            return
        }
        queue.insert(contentsOf: tracks, at: min(queue.count, i + 1))
        if unshuffledQueue != nil, let j = unshuffledQueue!.firstIndex(where: { $0.id == queue[i].id }) {
            unshuffledQueue!.insert(contentsOf: tracks, at: min(unshuffledQueue!.count, j + 1))
        }
        manualTokens.insert(contentsOf: tracks.map { _ in UUID() }, at: 0)
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
            manualCount: manualCount, sourceId: sourceId, sourceTitle: sourceTitle
        )
        UserDefaults.standard.set(try? JSONEncoder().encode(saved), forKey: Self.savedKey)
        // Every change to the queue, its order or its repeat lands here, so this is where the
        // standby and YouTube's own Up Next learn what plays next.
        syncStandby()
        syncNativeQueue()
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
        sourceId = saved.sourceId
        sourceTitle = saved.sourceTitle
        let manual = min(saved.manualCount ?? 0, max(0, saved.queue.count - index - 1))
        manualTokens = (0..<manual).map { _ in UUID() }
        needsLoad = true
    }

    // MARK: Internals

    private func load(index: Int, keepingManual: Bool = false) {
        let index = moveCurrent(to: index, keepingManual: keepingManual)
        isLoading = true
        // Any native move is over: this load is what plays. The page drops a queueing under way
        // when it navigates.
        endNativeAdvance()
        nativeTarget = nil
        nativeSource = nil
        isNativeQueued = false
        nativeFailures = [:]
        handedOver = canHandOver(to: queue[index].id)
        if handedOver {
            handOver()
        } else {
            trace("fallback load \(queue[index].id) on \(describe(bridge)): \(whyNotHandedOver(to: queue[index].id))")
            bridge.load(videoId: queue[index].id)
        }
        watchChromeStart(queue[index].id)
        recents?.recordPlayed(queue[index], artwork: liveArtworkURL)
        save()
    }

    /// Makes `index` the current song (moving the hand-queued ones along) and resets what's
    /// shown for it, for a load or for following the page's own move. Returns where it landed.
    private func moveCurrent(to index: Int, keepingManual: Bool) -> Int {
        var index = index
        if !keepingManual {
            adjustManual(for: index)
            if let moved = pendingLoadIndex { index = moved; pendingLoadIndex = nil }
        }
        currentIndex = index
        needsLoad = false
        streamOffset = 0
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
        wantsAutoplayNudge = true
        return index
    }

    private func setPlayingOptimistically(_ playing: Bool) {
        isPlaying = playing
        trustWebPlayStateAfter = .now.addingTimeInterval(0.6)
    }

    private func resetLiveState() {
        isPlaying = false
        currentTime = 0
        duration = 0
        songDuration = 0
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
            if let advance = nativeAdvance {
                // The move from the song that ended is already under way; a second `ended`
                // (from it, or the page's own churn) mustn't start another.
                trace("TRACK_ENDED \(videoId ?? "nil") ignored: native move \(advance.from.id) → \(advance.targetId) under way")
                return
            }
            guard videoId == current?.id, let i = currentIndex else { return }
            if beginNativeAdvance(endedAt: .now) { return }
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
            if let advance = nativeAdvance, videoId == advance.targetId {
                adoptNativeAdvance(advance, soundingAt: .now)
            }
            if videoId == chromeAwaitingStart { endChromeStartWatch() }
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
            logGap(old: trace.old, new: trace.new, mode: trace.mode, from: trace.endedAt, to: .now)
        case .state(let s):
            apply(s)
        case .queuedNext(let videoId, let ok, let reason):
            nativeQueued(videoId, ok: ok, reason: reason)
        case .playbackError(let videoId, let reason):
            playbackFailed(videoId, reason: reason)
        case .cued, .cueFailed:
            break
        }
    }

    // MARK: Gapless playback

    /// The song that plays when the current one ends by itself, as `handle(.ended)` picks it;
    /// nil when YouTube Music's own continuation takes over.
    var followingTrack: Track? { followingIndex.map { queue[$0] } }

    private var followingIndex: Int? {
        guard let i = currentIndex, queue.indices.contains(i) else { return nil }
        if repeatMode == .one { return i }
        if i + 1 < queue.count { return i + 1 }
        return repeatMode == .all && !queue.isEmpty ? 0 : nil
    }

    /// Points the standby at `followingTrack`, re-cueing only when that changed. It waits until
    /// the current song is under way (its first report is in), so the two don't fight for the
    /// network, and it isn't created at all until something has played.
    private func syncStandby() {
        guard gaplessMode == .secondPlayer else { tearDownStandby(); return }
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
        gaplessMode == .secondPlayer && standby != nil && isStandbyReady && standbyTrackId == videoId && pendingSeek == nil
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

    // MARK: Native queue

    /// Native queue mode: keeps YouTube Music's own Up Next holding `followingTrack` straight
    /// after the playing song, so the page's player moves on to it by itself when the song ends.
    /// Asks again only when what plays next (or the song playing) changed. Not for repeat one,
    /// which replays through Lilt's own load: a second copy of the playing song in YouTube's
    /// queue couldn't be told from the first, and YouTube's own repeat is left alone. Nor when
    /// the next entry is the same song again, for the same reason.
    private func syncNativeQueue() {
        guard gaplessMode.usesNativeQueue else { clearNativeQueue(); return }
        if let advance = nativeAdvance {
            // The queue changed under a move already under way: load what plays next now.
            if followingTrack?.id != advance.targetId {
                fallBackFromNativeAdvance("what plays next changed from \(advance.targetId) to \(followingTrack?.id ?? "nothing")")
            }
            return
        }
        guard let current else { clearNativeQueue(); return }
        guard !needsLoad, !isLoading else { return }
        guard repeatMode != .one, let next = followingTrack, next.id != current.id else {
            if nativeTarget != nil { trace("native queue: nothing to hold after \(current.id) (\(whyNoNativeTarget))") }
            clearNativeQueue()
            return
        }
        guard nativeTarget != next.id || nativeSource != current.id else { return }
        let key = "\(current.id)>\(next.id)"
        guard nativeFailures[key, default: 0] < Self.nativeAttempts else { return }
        if nativeTarget != nil, !isNativeQueued { bridge.cancelQueueNext() }
        nativeTarget = next.id
        nativeSource = current.id
        isNativeQueued = false
        trace("native queue: asking for \(next.id) after \(current.id) on \(describe(bridge))")
        bridge.queueNext(videoId: next.id, after: current.id)
    }

    private var whyNoNativeTarget: String {
        if repeatMode == .one { return "repeat one replays through a load" }
        guard let next = followingTrack else { return "the queue ends here" }
        return next.id == current?.id ? "the next entry is the same song" : "unknown"
    }

    private func clearNativeQueue() {
        if nativeTarget != nil, !isNativeQueued { bridge.cancelQueueNext() }
        nativeTarget = nil
        nativeSource = nil
        isNativeQueued = false
    }

    /// The page's answer to `queueNext`. One for a song or a source that's no longer the one
    /// asked about is stale; a failure is retried at the next save, up to `nativeAttempts`.
    private func nativeQueued(_ videoId: String, ok: Bool, reason: String) {
        guard videoId == nativeTarget, !isNativeQueued, let source = nativeSource else {
            trace("native queue: answer for \(videoId) (\(reason)) dropped, asking for \(nativeTarget ?? "nothing")")
            return
        }
        guard ok, current?.id == source, followingTrack?.id == videoId else {
            let key = "\(source)>\(videoId)"
            nativeFailures[key, default: 0] += 1
            trace("native queue: \(videoId) after \(source) failed (\(ok ? "stale" : reason)), attempt \(nativeFailures[key]!) of \(Self.nativeAttempts)")
            nativeTarget = nil
            nativeSource = nil
            return
        }
        isNativeQueued = true
        trace("native queue: \(videoId) confirmed after \(source) (\(reason))")
    }

    /// The song ended by itself: with what plays next confirmed in YouTube's Up Next, let the
    /// page's player move on to it rather than loading it. False to load it the ordinary way.
    private func beginNativeAdvance(endedAt: Date?) -> Bool {
        guard gaplessMode.usesNativeQueue else { return false }
        guard let current, let next = followingTrack, repeatMode != .one,
              isNativeQueued, nativeTarget == next.id, nativeSource == current.id else {
            trace("no native move on \(describe(bridge)): \(whyNotNativeAdvance)")
            return false
        }
        let advance = NativeAdvance(from: current, targetId: next.id, endedAt: endedAt)
        nativeAdvance = advance
        // The old song's paused, ended reports mustn't flip the button while the page moves on.
        trustWebPlayStateAfter = .now.addingTimeInterval(1.5)
        trace("native move started: \(current.id) → \(next.id) on \(describe(bridge))" + (endedAt == nil ? " (no ended)" : ""))
        nativeWatch = Task { [weak self, timeout = nativeAdvanceTimeout, token = advance.id, target = advance.targetId] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled, let self, self.nativeAdvance?.id == token else { return }
            if self.isChromeActive {
                self.chromeFailed("stuck: the page didn't reach \(target) within \(timeout)")
            } else {
                self.fallBackFromNativeAdvance("the page didn't reach \(target) within \(timeout)")
            }
        }
        return true
    }

    private var whyNotNativeAdvance: String {
        if repeatMode == .one { return "repeat one" }
        guard let next = followingTrack else { return "nothing plays next" }
        if nativeTarget != next.id || nativeSource != current?.id { return "YouTube's Up Next wasn't asked for \(next.id) after \(current?.id ?? "nil")" }
        if !isNativeQueued { return "YouTube's Up Next hadn't confirmed \(next.id)" }
        return "unknown"
    }

    private func endNativeAdvance() {
        nativeAdvance = nil
        nativeWatch?.cancel()
        nativeWatch = nil
    }

    /// The page's player reached the song Lilt expected: it becomes the current one, with the
    /// history, recents, Now Playing and the rest following, and nothing is loaded. With sound
    /// already under way (`soundingAt`, or a playing snapshot), the gap is logged here.
    private func adoptNativeAdvance(
        _ advance: NativeAdvance, soundingAt: Date? = nil, from s: PlaybackSnapshot? = nil, continuation: Continuation? = nil
    ) {
        let continuation = continuation ?? advance.continuation
        endNativeAdvance()
        guard let index = followingIndex, queue[index].id == advance.targetId else {
            nativeAdvance = advance
            fallBackFromNativeAdvance("\(advance.targetId) is no longer what plays next")
            return
        }
        let landed = moveCurrent(to: index, keepingManual: false)
        let new = queue[landed]
        isLoading = false
        handedOver = false
        nativeTarget = nil
        nativeSource = nil
        isNativeQueued = false
        nativeFailures = [:]
        let mode = isChromeActive ? "chrome" : "native"
        recents?.recordPlayed(new, artwork: liveArtworkURL)
        if let continuation {
            // One stream: the new song is the same `<video>` playing on, so there was no silence
            // to time. What's logged is from the old song's end on that timeline to the new id
            // showing up, which is YouTube's metadata catching up.
            streamOffset = continuation.boundary
            trace("native move adopted: \(advance.from.id) → \(new.id) on \(describe(bridge)), same-element continuation (the <video> played on past \(advance.from.id)'s \(Int(continuation.boundary - continuation.previousOffset))s end)")
            logGap(old: advance.from, new: new, mode: mode, from: advance.endedAt ?? .now, to: .now)
            save()
            return
        }
        trace("native move adopted: \(advance.from.id) → \(new.id) on \(describe(bridge)), new stream")
        // When the new song started sounding: now, for its `playing`; or as far back as its
        // position says, for a snapshot that has it playing already.
        let sounded = soundingAt ?? s.flatMap { $0.isPlaying ? Date.now.addingTimeInterval(-$0.currentTime) : nil }
        if let sounded {
            logGap(old: advance.from, new: new, mode: mode, from: advance.endedAt ?? sounded, to: sounded)
        } else {
            gap = GapTrace(old: advance.from, new: new, mode: mode, endedAt: advance.endedAt ?? .now)
        }
        save()
    }

    /// One continuous stream: where the new song starts on the `<video>`'s timeline (the old
    /// song's end), and where the old song started.
    struct Continuation {
        let boundary: Double
        let previousOffset: Double
    }

    /// The page didn't make the expected move (it went elsewhere, didn't get there in time, or
    /// what plays next changed meanwhile): load what plays next the ordinary way.
    /// True when it loaded something.
    @discardableResult
    private func fallBackFromNativeAdvance(_ reason: String) -> Bool {
        guard let advance = nativeAdvance else { return false }
        endNativeAdvance()
        guard let index = followingIndex else {
            trace("native move \(advance.from.id) → \(advance.targetId) abandoned: \(reason), and nothing plays next")
            return false
        }
        trace("fallback load \(queue[index].id) on \(describe(bridge)): \(reason)")
        load(index: index)
        let mode = isChromeActive ? "chrome fallback" : "native fallback"
        if let new = current { gap = GapTrace(old: advance.from, new: new, mode: mode, endedAt: advance.endedAt ?? .now) }
        return true
    }

    // MARK: Chrome mode

    /// The player page's user agent changed: reload it on the song playing, where it was, so
    /// the page reads its browser again. A paused song reloads when you press play.
    private func reloadForUserAgent() {
        if nativeAdvance != nil {
            fallBackFromNativeAdvance("the player page reloads as \(userAgentName)")
            return
        }
        guard let i = currentIndex, current != nil, !needsLoad else { return }
        guard isPlaying || isLoading else {
            trace("player page reloads as \(userAgentName) when \(queue[i].id) plays again")
            needsLoad = true
            return
        }
        pendingSeek = currentTime > 1 ? currentTime : nil
        trace("player page reloads as \(userAgentName) on \(queue[i].id) at \(Int(currentTime))s")
        load(index: i, keepingManual: true)
    }

    /// The page says it couldn't play a song. In Chrome mode that's a failure to fall back from;
    /// otherwise it's only traced.
    private func playbackFailed(_ videoId: String?, reason: String) {
        let about = videoId ?? "nil"
        guard isChromeActive else {
            trace("playback error on \(describe(bridge)) for \(about): \(reason)")
            return
        }
        let relevant = videoId == nil || videoId == current?.id
            || (nativeAdvance.map { videoId == $0.targetId } ?? false)
        guard relevant else {
            trace("chrome mode playback error for \(about) ignored, playing \(current?.id ?? "nil"): \(reason)")
            return
        }
        chromeFailed("\(about): \(reason)")
    }

    /// Chrome mode couldn't play the song (an error, or it didn't start in time). Never silence:
    /// the song is loaded again the ordinary way, and after `chromeFailureLimit` in a row the
    /// player page goes back to Safari's user agent for the rest of the session.
    private func chromeFailed(_ what: String) {
        endChromeStartWatch()
        chromeFailures += 1
        trace("chrome mode playback error \(what) (\(chromeFailures) of \(Self.chromeFailureLimit) in a row) on \(describe(bridge))")
        if chromeFailures >= Self.chromeFailureLimit {
            isChromeModeSuspended = true
            chromeFailures = 0
            bridge.setUserAgent(playerUserAgent)
            bridgeUserAgent = playerUserAgent
            trace("chrome mode playback error: giving up on Chrome mode for this session; the player page goes back to the Safari user agent and keeps following YouTube's own queue")
        }
        if nativeAdvance != nil {
            fallBackFromNativeAdvance("chrome mode playback error")
        } else if let i = currentIndex, current != nil {
            pendingSeek = currentTime > 1 ? currentTime : nil
            trace("fallback load \(queue[i].id) on \(describe(bridge)) as \(userAgentName): chrome mode playback error")
            load(index: i, keepingManual: true)
        }
    }

    /// Chrome mode: a loaded song that isn't heard within `chromeStartTimeout` is a failure.
    private func watchChromeStart(_ id: String) {
        endChromeStartWatch()
        guard isChromeActive else { return }
        chromeAwaitingStart = id
        chromeStartWatch = Task { [weak self, timeout = chromeStartTimeout] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled, let self, self.chromeAwaitingStart == id, self.current?.id == id else { return }
            self.chromeFailed("stuck: \(id) didn't start within \(timeout)")
        }
    }

    private func endChromeStartWatch() {
        chromeAwaitingStart = nil
        chromeStartWatch?.cancel()
        chromeStartWatch = nil
    }

    /// Native queue mode, from a snapshot of the page's player: whether it is moving on (or has
    /// moved on) from the current song by itself. True when the snapshot was dealt with here.
    private func followNativeMove(_ s: PlaybackSnapshot, videoId: String) -> Bool {
        guard gaplessMode.usesNativeQueue, let current else { return false }
        if let advance = nativeAdvance {
            if videoId == advance.targetId { adoptNativeAdvance(advance, from: s); return false }
            if videoId == advance.from.id { return false }
            fallBackFromNativeAdvance("the page moved to \(videoId), not \(advance.targetId)")
            return true
        }
        guard !isLoading, isNativeQueued, nativeSource == current.id, let target = nativeTarget,
              followingTrack?.id == target else { return false }
        let time = s.currentTime - streamOffset
        let pastEnd = songDuration > 0 && time > songDuration + 1
        let continuation = pastEnd ? Continuation(boundary: streamOffset + songDuration, previousOffset: streamOffset) : nil
        if videoId == target {
            // The page went straight on to the next song without an `ended`: in the same
            // stream when its timeline carries on past the old song's end, else a new one.
            let endedAt = pastEnd ? Date.now.addingTimeInterval(-(time - songDuration)) : nil
            if beginNativeAdvance(endedAt: endedAt), let advance = nativeAdvance {
                adoptNativeAdvance(advance, from: s, continuation: continuation)
            }
            return false
        }
        // One continuous stream: the same element plays on past the old song's end.
        if videoId == current.id, pastEnd, s.duration - streamOffset > songDuration + 1 {
            let endedAt = Date.now.addingTimeInterval(-(time - songDuration))
            trace("native queue: \(current.id) played on past its \(Int(songDuration))s end in the same element")
            if beginNativeAdvance(endedAt: endedAt) { nativeAdvance?.continuation = continuation }
            return true
        }
        return false
    }

    // MARK: Gapless trace (DEBUG)

    /// `Lilt gapless: …` lines in the unified log, one per step of a handover, to see in the
    /// running app where one stops. Nothing in release builds.
    private func trace(_ message: @autoclosure () -> String) {
        #if DEBUG
        DebugLog.player("Lilt gapless: " + message())
        #endif
    }

    /// `Lilt gap <ms>ms old→new (mode)`: the silence between one song ending and the next
    /// sounding, never below 0 (a continuous stream has none).
    private func logGap(old: Track, new: Track, mode: String, from: Date, to: Date) {
        #if DEBUG
        let ms = max(0, Int((to.timeIntervalSince(from) * 1000).rounded()))
        DebugLog.player("Lilt gap \(ms)ms \(old.title)→\(new.title) (\(mode))")
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
        case .queuedNext(let id, let ok, let reason):
            trace("QUEUE_NEXT from \(describe(player)): \(id) \(ok ? "ok" : "failed") (\(reason)), asked for \(nativeTarget ?? "nil")")
        case .cueFailed(let id):
            trace("CUE_FAILED from \(describe(player)): \(id), standby holds \(standbyTrackId ?? "nil")")
        default:
            break
        }
    }

    /// Which of `canHandOver`'s conditions failed.
    private func whyNotHandedOver(to videoId: String) -> String {
        if gaplessMode != .secondPlayer { return "gapless mode is \(gaplessMode.rawValue)" }
        guard standby != nil else { return "no standby yet" }
        if pendingSeek != nil { return "resuming partway through" }
        if standbyTrackId != videoId { return "standby holds \(standbyTrackId ?? "nothing"), not \(videoId)" }
        if !isStandbyReady { return "standby still cueing \(videoId)" }
        return "unknown"
    }

    private func apply(_ s: PlaybackSnapshot) {
        guard let videoId = s.videoId else { return }
        if followNativeMove(s, videoId: videoId) { return }
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
            syncNativeQueue()
        }
        // WebKit only registers with Now Playing once the page actually plays. A snapshot of
        // YouTube's own restored (paused) player after a relaunch doesn't count, so the bridge
        // keeps Lilt's entry until our restored track is loaded and running.
        if !needsLoad, s.isPlaying { hasWebSession = true }
        if s.isPlaying == isPlaying || Date.now >= trustWebPlayStateAfter {
            isPlaying = s.isPlaying
        }
        if let target = pendingSeek, s.isPlaying {
            pendingSeek = nil
            bridge.seek(to: target)
            return
        }
        // After a same-stream move the `<video>`'s clock runs on from the old song; times are
        // shown from where this one starts. A clock back before that start is a new stream.
        if streamOffset > 0, s.currentTime + 1 < streamOffset { streamOffset = 0 }
        currentTime = max(0, s.currentTime - streamOffset)
        if abs(currentTime - lastSavedTime) > 5 { save() }
        duration = max(0, s.duration - streamOffset)
        if songDuration == 0 { songDuration = duration }
        if s.isPlaying, videoId == current?.id {
            if videoId == chromeAwaitingStart { endChromeStartWatch() }
            // Really under way: Chrome mode's run of failures is over.
            if currentTime > 2, chromeFailures > 0 { chromeFailures = 0 }
        }
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
