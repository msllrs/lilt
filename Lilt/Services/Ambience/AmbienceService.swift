import Foundation
import Observation
import OSLog
import WebKit

/// Background sound under the music: long recordings of rain, wind, fire, ocean and deep noise
/// from YouTube Music, each on a hidden page of its own while it is on, and a live stream of the
/// listener's choosing, air traffic control or otherwise. The pages stay out of Now Playing and
/// the history (see `PlayerBridge`'s ambient mode), and keep going when the music is paused by
/// hand. When the system pauses it instead (headphones taken out), they go quiet with it.
@MainActor
@Observable
final class AmbienceService {
    enum Sound: String, CaseIterable, Identifiable, Codable {
        case rain, wind, fire, ocean, deep
        var id: String { rawValue }
        var name: String {
            switch self {
            case .rain: "Rain"
            case .wind: "Wind"
            case .fire: "Fire"
            case .ocean: "Ocean"
            case .deep: "Deep noise"
            }
        }
        var symbol: String {
            switch self {
            case .rain: "cloud.rain"
            case .wind: "wind"
            case .fire: "flame"
            case .ocean: "water.waves"
            case .deep: "waveform"
            }
        }
        /// The YouTube Music track it plays: an hour or more of one recording, picked from a
        /// search on 2026-11-17, so it loops rarely.
        var videoId: String {
            switch self {
            case .rain: "xsJNJIAFfnY"   // Indoor Rain Sounds – No Thunder, The Guild of Ambience, 1:00:01
            case .wind: "witZqY-uH3w"   // Howling Wind Through the Mountain Pass, Masters of the Elements, 1:00:00
            case .fire: "dIdkB9h2s7M"   // Fireplace Sounds with Crackling & Hissing: One Hour (Loopable), Stardust Vibes
            case .ocean: "iPTGxlrVOO0"  // 10 Hours of Continuous Ocean Waves to Sleep to, 10 Hour Recordings
            case .deep: "G3JeHAVCSRI"   // Smoothed Brown Noise, Pt. I, 8-Hour Sound Machines, 4:16:01
            }
        }
    }

    /// The live feed to play, supplied by the listener: a plain audio stream URL (an Icecast or
    /// SHOUTcast mount, or any HTTP audio stream) they are entitled to listen to in an app. Lilt
    /// ships no feed of its own. It plays the stream on a page, the way a browser does, which is
    /// what these hosts serve.
    var streamURL: String = "" { didSet { if isStreaming { startStream() }; save() } }

    /// The sounds playing now. Not remembered: a relaunch shouldn't start raining on its own.
    private(set) var active: Set<Sound> = []
    /// Level of the whole ambience bed under the music.
    var volume: Float = 0.5 {
        didSet {
            applyVolumes()
            save()
        }
    }
    /// Each sound's own level, under the bed's: the ring round its button. Full until set.
    private(set) var levels: [Sound: Float] = [:]

    func level(of sound: Sound) -> Float { levels[sound] ?? 1 }

    func setLevel(_ level: Float, for sound: Sound) {
        levels[sound] = max(0, min(1, level))
        players[sound]?.setVolume(Double(volume * self.level(of: sound)))
        save()
    }

    private func applyVolumes() {
        for (sound, player) in players { player.setVolume(Double(volume * level(of: sound))) }
    }
    /// Sounds switched on whose page hasn't started to sound yet; their buttons pulse.
    private(set) var loading: Set<Sound> = []
    private(set) var isStreaming = false
    /// Where the feed is: a live one takes ten seconds or so to buffer, and a dead mount never
    /// arrives, so the switch shows which.
    enum StreamState: Equatable { case off, connecting, playing, failed }
    private(set) var streamState: StreamState = .off
    var streamVolume: Float = 0.6 { didSet { streamPage?.setVolume(streamVolume); save() } }

    /// Anything audible from here.
    var isOn: Bool { !active.isEmpty || isStreaming }
    /// The system paused the music while the bed was on (headphones taken out): the switches
    /// stay as they are, but their pages are paused, and the feed is reloaded when the music
    /// plays again.
    private(set) var isHeldForSystemPause = false

    private static let log = Logger(subsystem: "com.msllrs.Lilt", category: "ambience")
    private var streamPage: (any StreamPaging)?

    /// Makes the hidden page a sound plays on, signed in like the music's. Wired by the app; nil
    /// in tests, where switching a sound on plays nothing.
    @ObservationIgnored var makePlayer: (@MainActor () -> any PlayerBridging)?
    /// Makes the feed's page. Wired by the app; a fake in tests.
    @ObservationIgnored var makeStreamPage: (@MainActor () -> any StreamPaging) = { StreamPage() }
    /// Puts a page's view in a window, where it has to be to keep playing. Wired by the app.
    @ObservationIgnored var hostWebView: ((WKWebView) -> Void)?
    /// A page for each sound that is on, and only while it is: each one is a whole YouTube Music
    /// page, a few hundred megabytes.
    @ObservationIgnored private var players: [Sound: any PlayerBridging] = [:]
    /// Where the settings are remembered: the app's defaults, or a suite of the tests' own.
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        restore()
    }

    func toggle(_ sound: Sound) {
        if active.contains(sound) {
            active.remove(sound)
            stop(sound)
        } else {
            // Switching a sound on while the music is paused by the system is a request to hear
            // the bed again, so it and the rest come back now.
            if isHeldForSystemPause { releaseAfterSystemPause() }
            active.insert(sound)
            start(sound)
        }
        clearHoldIfSilent()
    }

    private func start(_ sound: Sound) {
        guard players[sound] == nil, let player = makePlayer?() else { return }
        players[sound] = player
        loading.insert(sound)
        player.onEvent = { [weak self] event in self?.handle(event, of: sound) }
        if let view = player.webView { hostWebView?(view) }
        // Given before it loads, so the page starts at this level rather than YouTube's.
        player.setVolume(Double(volume * level(of: sound)))
        player.load(videoId: sound.videoId)
    }

    private func stop(_ sound: Sound) {
        loading.remove(sound)
        guard let player = players.removeValue(forKey: sound) else { return }
        player.onEvent = nil
        player.unload()
        player.webView?.removeFromSuperview()
    }

    private func handle(_ event: PlayerEvent, of sound: Sound) {
        guard let player = players[sound] else { return }
        switch event {
        case .playing:
            loading.remove(sound)
            // The page can finish loading after the system pause asked it to pause, while its
            // script wasn't there yet; a page that starts now goes quiet again.
            if isHeldForSystemPause { player.pause() }
        case .state(let snapshot):
            if isHeldForSystemPause, snapshot.isPlaying { player.pause() }
            // Back to the start a moment before the end, so the page never finishes the track
            // and autoplays something else.
            if snapshot.duration > 30, snapshot.currentTime > snapshot.duration - 1.5 { player.seek(to: 0) }
        case .ended:
            player.load(videoId: sound.videoId)
        case .playbackError(_, let reason):
            Self.log.error("ambience \(sound.rawValue, privacy: .public) failed: \(reason, privacy: .public)")
        default:
            break
        }
    }

    func setStreaming(_ on: Bool) {
        if on, isHeldForSystemPause {
            // Like switching a sound on: the listener wants to hear it, so bring the bed back.
            isStreaming = true
            releaseAfterSystemPause()
        } else {
            isStreaming = on
            if on { startStream() } else { stopStream() }
        }
        clearHoldIfSilent()
    }

    /// The system paused the music (headphones taken out, say): hold the bed silent, with the
    /// drawer's switches still on, until the music plays again. Pausing the feed's page would
    /// leave it buffered behind live, so it is stopped and reloaded on release.
    func holdForSystemPause() {
        guard isOn, !isHeldForSystemPause else { return }
        isHeldForSystemPause = true
        for player in players.values { player.pause() }
        stopStreamPage()
        streamState = .off
    }

    /// The music is playing again: let the held sounds and feed go on.
    func releaseAfterSystemPause() {
        guard isHeldForSystemPause else { return }
        isHeldForSystemPause = false
        guard isOn else { return }
        for player in players.values { player.play() }
        if isStreaming { startStream() }
    }

    /// Nothing left to hold.
    private func clearHoldIfSilent() {
        if !isOn { isHeldForSystemPause = false }
    }

    private func stopStream() {
        stopStreamPage()
        streamState = .off
    }

    private func stopStreamPage() {
        streamPage?.stop()
        streamPage = nil
    }

    func stopAll() {
        for sound in active { toggle(sound) }
        setStreaming(false)
    }

    private func startStream() {
        guard let url = StreamAddress.stream(from: streamURL) else {
            stopStreamPage()
            streamState = .failed
            return
        }
        // One page at a time: a new URL takes over from the last.
        stopStreamPage()
        // Held for a system pause: remember the address, but don't sound it until release.
        guard !isHeldForSystemPause else {
            streamState = .off
            return
        }
        streamState = .connecting
        let page = makeStreamPage()
        page.onEvent = { [weak self] event in self?.handle(event) }
        if let view = page.webView { hostWebView?(view) }
        page.load(url, volume: streamVolume)
        streamPage = page
        let level = streamVolume
        Self.log.debug("feed start \(url.absoluteString, privacy: .private) volume \(level)")
    }

    private func handle(_ event: StreamEvent) {
        switch event {
        case .playing:
            streamState = .playing
        case .waiting:
            // A live feed buffers for a few seconds at the start, and again if it slips behind;
            // a failure is final until the listener tries again.
            guard streamState != .failed else { return }
            streamState = .connecting
        case .failed(let reason):
            Self.log.error("feed failed: \(reason, privacy: .public)")
            streamState = .failed
        }
    }

    // MARK: Remembered settings

    private static let key = "ambience"
    private struct Saved: Codable { var volume: Float; var streamVolume: Float; var streamURL: String?; var levels: [String: Float]? }

    private func save() {
        let levels = Dictionary(uniqueKeysWithValues: levels.map { ($0.key.rawValue, $0.value) })
        defaults.set(try? JSONEncoder().encode(Saved(volume: volume, streamVolume: streamVolume, streamURL: streamURL, levels: levels)), forKey: Self.key)
    }

    private func restore() {
        guard let data = defaults.data(forKey: Self.key), let saved = try? JSONDecoder().decode(Saved.self, from: data) else { return }
        volume = saved.volume
        streamVolume = saved.streamVolume
        streamURL = saved.streamURL ?? ""
        levels = Dictionary(uniqueKeysWithValues: (saved.levels ?? [:]).compactMap { key, value in Sound(rawValue: key).map { ($0, value) } })
    }
}
