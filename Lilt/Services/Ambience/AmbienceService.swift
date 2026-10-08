import AVFoundation
import Foundation
import Observation

/// Background sound under the music: ambience generated live (rain, wind, fire, ocean, deep
/// noise, no samples and no licences) and live air traffic control streams. Its own audio
/// graph, outside the web player, so it can't touch DRM or the Media Session, and it keeps
/// going when the music pauses.
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
    }

    /// A live tower or approach feed. The URLs are LiveATC mounts; their terms allow personal
    /// listening, not redistribution, so this stays a listener and ships no feed of its own.
    struct Station: Identifiable, Hashable, Codable {
        var id: String { url }
        let name: String
        let url: String
    }

    /// Mounts checked against the server on 2026-10-08; LiveATC serves only the ones it has.
    static let stations: [Station] = [
        Station(name: "New York JFK", url: "https://d.liveatc.net/kjfk_twr"),
        Station(name: "JFK Ground", url: "https://d.liveatc.net/kjfk_gnd"),
        Station(name: "Newark", url: "https://d.liveatc.net/kewr_twr"),
        Station(name: "LaGuardia", url: "https://d.liveatc.net/klga_twr"),
        Station(name: "Atlanta", url: "https://d.liveatc.net/katl_twr"),
        Station(name: "Los Angeles", url: "https://d.liveatc.net/klax_twr"),
        Station(name: "San Francisco", url: "https://d.liveatc.net/ksfo_twr"),
        Station(name: "SFO Ground", url: "https://d.liveatc.net/ksfo_gnd"),
        Station(name: "Tokyo Haneda", url: "https://d.liveatc.net/rjtt_twr"),
    ]

    /// The sounds playing now. Not remembered: a relaunch shouldn't start raining on its own.
    private(set) var active: Set<Sound> = []
    /// Level of the whole ambience bed under the music.
    var volume: Float = 0.5 { didSet { engine.mainMixerNode.outputVolume = volume; save() } }
    var station: Station = stations[0] { didSet { if isStreaming { startStream() }; save() } }
    private(set) var isStreaming = false
    /// Where the feed is: a live one takes ten seconds or so to buffer, and a dead mount never
    /// arrives, so the switch shows which.
    enum StreamState { case off, connecting, playing, failed }
    private(set) var streamState: StreamState = .off
    var streamVolume: Float = 0.6 { didSet { stream?.volume = streamVolume; save() } }

    /// Anything audible from here.
    var isOn: Bool { !active.isEmpty || isStreaming }

    private let engine = AVAudioEngine()
    private var nodes: [Sound: AVAudioSourceNode] = [:]
    private var stream: AVPlayer?
    private var streamObservers: [NSKeyValueObservation] = []

    init() {
        restore()
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        for sound in Sound.allCases {
            let node = Self.makeNode(for: sound, format: format)
            node.volume = 0
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            nodes[sound] = node
        }
        engine.mainMixerNode.outputVolume = volume
    }

    /// The render block runs on the audio thread. Written inside this main-actor class it would
    /// inherit the actor and trap the first time it was called, so the node is built here, off
    /// the actor, with a generator of its own.
    nonisolated private static func makeNode(for sound: Sound, format: AVAudioFormat) -> AVAudioSourceNode {
        let generator = AmbienceGenerator(sound)
        return AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let data = buffers[0].mData else { return noErr }
            generator.render(data.assumingMemoryBound(to: Float.self), Int(frameCount))
            return noErr
        }
    }

    func toggle(_ sound: Sound) {
        if active.contains(sound) { active.remove(sound) } else { active.insert(sound) }
        // The graph runs only while something is on; a running engine with every source at
        // zero still renders them all.
        if !active.isEmpty, !engine.isRunning { try? engine.start() }
        for (each, node) in nodes { node.volume = active.contains(each) ? 1 : 0 }
        if active.isEmpty, engine.isRunning { engine.stop() }
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
        guard let url = URL(string: station.url) else { return }
        stream?.pause()
        // The feed servers refuse AVFoundation's own user agent (a permission error before any
        // audio arrives); as a browser they answer. A live feed at 16kbps also takes a while to
        // buffer, so the player is told to start as soon as it can rather than wait to be safe.
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            "Icy-MetaData": "0",
        ]])
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 2
        let player = AVPlayer(playerItem: item)
        player.automaticallyWaitsToMinimizeStalling = false
        player.volume = streamVolume
        streamState = .connecting
        streamObservers = [
            player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
                let playing = player.timeControlStatus == .playing
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
    }

    // MARK: Remembered settings

    private static let key = "ambience"
    private struct Saved: Codable { var volume: Float; var streamVolume: Float; var station: Station? }

    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(Saved(volume: volume, streamVolume: streamVolume, station: station)), forKey: Self.key)
    }

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: Self.key), let saved = try? JSONDecoder().decode(Saved.self, from: data) else { return }
        volume = saved.volume
        streamVolume = saved.streamVolume
        // A remembered station that is no longer in the list was a mount the server didn't
        // have; falling back beats a switch that never makes a sound.
        if let station = saved.station, Self.stations.contains(station) { self.station = station }
    }
}

/// One ambience sound, rendered on the audio thread from noise and a few filters: no state
/// shared with anything else, so it is safe to drive from the render block.
private final class AmbienceGenerator: @unchecked Sendable {
    private let sound: AmbienceService.Sound
    // xorshift noise
    private var seed: UInt32 = 0x9E37_79B9
    // pink noise (Paul Kellet's filter)
    private var b0: Float = 0, b1: Float = 0, b2: Float = 0, b3: Float = 0, b4: Float = 0, b5: Float = 0, b6: Float = 0
    private var brown: Float = 0
    private var lowpass: Float = 0
    private var highpassState: Float = 0
    // slow movements: gusts, swells, flicker
    private var slow: Float = 0.5, slowTarget: Float = 0.5, slowCountdown = 0
    private var phase: Float = 0
    // sparse events: rain drops, fire crackles
    private var event: Float = 0

    init(_ sound: AmbienceService.Sound) { self.sound = sound }

    private func white() -> Float {
        seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5
        return Float(Int32(bitPattern: seed)) / Float(Int32.max)
    }

    private func pink(_ w: Float) -> Float {
        b0 = 0.99886 * b0 + w * 0.0555179
        b1 = 0.99332 * b1 + w * 0.0750759
        b2 = 0.96900 * b2 + w * 0.1538520
        b3 = 0.86650 * b3 + w * 0.3104856
        b4 = 0.55000 * b4 + w * 0.5329522
        b5 = -0.7616 * b5 - w * 0.0168980
        let out = b0 + b1 + b2 + b3 + b4 + b5 + b6 + w * 0.5362
        b6 = w * 0.115926
        return out * 0.11
    }

    private func brownNoise(_ w: Float) -> Float {
        brown = (brown + 0.02 * w) / 1.02
        return brown * 3.5
    }

    /// A value that wanders slowly between random targets, for gusts and flicker.
    private func wander(every samples: Int, rate: Float) -> Float {
        if slowCountdown <= 0 {
            slowTarget = 0.5 + 0.5 * white()
            slowCountdown = samples / 2 + Int(Float(samples) * 0.5 * (0.5 + 0.5 * white()))
        }
        slowCountdown -= 1
        slow += (slowTarget - slow) * rate
        return slow
    }

    func render(_ out: UnsafeMutablePointer<Float>, _ count: Int) {
        for i in 0..<count {
            let w = white()
            var sample: Float
            switch sound {
            case .rain:
                // Hiss from pink noise above a few hundred hertz, with a steady patter of drops.
                let p = pink(w)
                highpassState += 0.06 * (p - highpassState)
                let hiss = (p - highpassState) * 0.9
                if abs(white()) < 0.0015 { event = 0.5 + 0.5 * abs(white()) }
                event *= 0.993
                sample = hiss + event * white() * 0.5
            case .wind:
                // Low noise under slow gusts.
                let b = brownNoise(w)
                lowpass += 0.015 * (b - lowpass)
                let gust = wander(every: 48_000 * 3, rate: 0.00003)
                sample = lowpass * (0.35 + 0.65 * gust) * 1.8
            case .fire:
                // A low roar that flickers, with sparse crackles.
                let b = brownNoise(w)
                lowpass += 0.03 * (b - lowpass)
                let flicker = wander(every: 48_000 / 4, rate: 0.0005)
                if abs(white()) < 0.00025 { event = 0.6 + 0.4 * abs(white()) }
                event *= 0.96
                sample = lowpass * (0.5 + 0.5 * flicker) * 0.9 + event * white()
            case .ocean:
                // Pink noise rising and falling on a long swell.
                phase += 1 / (48_000 * 9)
                if phase > 1 { phase -= 1 }
                let swell = 0.5 - 0.5 * cos(phase * 2 * .pi)
                lowpass += 0.08 * (pink(w) - lowpass)
                sample = lowpass * (0.15 + 0.85 * swell) * 1.6
            case .deep:
                sample = brownNoise(w) * 0.7
            }
            out[i] = max(-1, min(1, sample))
        }
    }
}
