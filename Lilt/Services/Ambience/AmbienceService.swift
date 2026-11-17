import AVFoundation
import Foundation
import Observation
import OSLog
import WebKit

/// Background sound under the music: long recordings of rain, wind, fire, ocean and deep noise
/// from YouTube Music, each on a hidden page of its own while it is on, and a live stream of the
/// listener's choosing, air traffic control or otherwise. The pages stay out of Now Playing and
/// the history (see `PlayerBridge`'s ambient mode), and keep going when the music pauses.
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
    /// ships no feed of its own and does nothing to disguise itself to a server.
    var streamURL: String = "" { didSet { if isStreaming { startStream() }; save() } }

    /// The sounds playing now. Not remembered: a relaunch shouldn't start raining on its own.
    private(set) var active: Set<Sound> = []
    /// Level of the whole ambience bed under the music.
    var volume: Float = 0.5 {
        didSet {
            for player in players.values { player.setVolume(Double(volume)) }
            save()
        }
    }
    /// Sounds switched on whose page hasn't started to sound yet; their buttons pulse.
    private(set) var loading: Set<Sound> = []
    private(set) var isStreaming = false
    /// Where the feed is: a live one takes ten seconds or so to buffer, and a dead mount never
    /// arrives, so the switch shows which.
    enum StreamState { case off, connecting, playing, failed }
    private(set) var streamState: StreamState = .off
    var streamVolume: Float = 0.6 { didSet { stream?.volume = streamVolume; save() } }

    /// Anything audible from here.
    var isOn: Bool { !active.isEmpty || isStreaming }

    private static let log = Logger(subsystem: "com.msllrs.Lilt", category: "ambience")
    private var stream: AVPlayer?
    private var streamObservers: [NSKeyValueObservation] = []

    /// Makes the hidden page a sound plays on, signed in like the music's. Wired by the app; nil
    /// in tests, where switching a sound on plays nothing.
    @ObservationIgnored var makePlayer: (@MainActor () -> any PlayerBridging)?
    /// Puts a page's view in a window, where it has to be to keep playing. Wired by the app.
    @ObservationIgnored var hostWebView: ((WKWebView) -> Void)?
    /// A page for each sound that is on, and only while it is: each one is a whole YouTube Music
    /// page, a few hundred megabytes.
    @ObservationIgnored private var players: [Sound: any PlayerBridging] = [:]

    init() {
        restore()
    }

    func toggle(_ sound: Sound) {
        if active.contains(sound) {
            active.remove(sound)
            stop(sound)
        } else {
            active.insert(sound)
            start(sound)
        }
    }

    private func start(_ sound: Sound) {
        guard players[sound] == nil, let player = makePlayer?() else { return }
        players[sound] = player
        loading.insert(sound)
        player.onEvent = { [weak self] event in self?.handle(event, of: sound) }
        if let view = player.webView { hostWebView?(view) }
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
            player.setVolume(Double(volume))
        case .state(let snapshot):
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
        isStreaming = on
        if on { startStream() } else { stopStream() }
    }

    private func stopStream() {
        streamObservers = []
        stream?.pause()
        stream = nil
        streamState = .off
    }

    func stopAll() {
        for sound in active { toggle(sound) }
        setStreaming(false)
    }

    private func startStream() {
        guard let url = URL(string: streamURL.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme?.hasPrefix("http") == true else {
            streamState = .failed
            return
        }
        stream?.pause()
        // A live feed at a low bitrate takes a while to buffer, so the player is told to start
        // as soon as it can rather than wait to be safe.
        let item = AVPlayerItem(url: url)
        item.preferredForwardBufferDuration = 2
        let player = AVPlayer(playerItem: item)
        player.automaticallyWaitsToMinimizeStalling = false
        player.volume = streamVolume
        streamState = .connecting
        streamObservers = [
            player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
                let playing = player.timeControlStatus == .playing
                let status = player.timeControlStatus.rawValue, rate = player.rate, volume = player.volume, muted = player.isMuted
                let waiting = player.reasonForWaitingToPlay?.rawValue ?? "-"
                Self.log.debug("feed timeControlStatus \(status) rate \(rate) volume \(volume) muted \(muted) waiting \(waiting, privacy: .public)")
                Task { @MainActor in
                    guard let self, self.stream === player, self.streamState != .failed else { return }
                    self.streamState = playing ? .playing : .connecting
                }
            },
            item.observe(\.status, options: [.new]) { [weak self] item, _ in
                let failed = item.status == .failed
                Task { @MainActor in
                    guard let self, self.stream?.currentItem === item, failed else { return }
                    self.streamState = .failed
                }
            },
        ]
        player.play()
        stream = player
        Self.log.debug("feed start \(url.absoluteString, privacy: .private) volume \(player.volume) rate \(player.rate)")
    }

    // MARK: Remembered settings

    private static let key = "ambience"
    private struct Saved: Codable { var volume: Float; var streamVolume: Float; var streamURL: String? }

    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(Saved(volume: volume, streamVolume: streamVolume, streamURL: streamURL)), forKey: Self.key)
    }

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: Self.key), let saved = try? JSONDecoder().decode(Saved.self, from: data) else { return }
        volume = saved.volume
        streamVolume = saved.streamVolume
        streamURL = saved.streamURL ?? ""
    }
}
