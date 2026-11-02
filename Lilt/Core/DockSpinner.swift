import AppKit

/// Spins the cover on the Dock tile while a song plays, at the same speed as the disc in the
/// app's rows. The Dock only takes still images, so this hands it one frame after another.
/// Each frame is drawn the first time the lap reaches it and replayed from memory after that,
/// so once the first lap is done a frame costs only the handover to the Dock.
/// How fast the Dock tile spins, as Settings ▸ Dock offers it. Stored as frames per second
/// under `dockSpinFPS`, so a rate written by hand (`defaults write com.msllrs.Lilt dockSpinFPS
/// -int 12`) still counts. 8 looked steppy; 15 holds up at ordinary Dock sizes.
enum DockSpin: Int, CaseIterable, Identifiable {
    case off = 0
    case standard = 15
    case smooth = 30

    static let key = "dockSpinFPS"

    var id: Int { rawValue }
    var framesPerSecond: Int { rawValue }

    var title: String {
        switch self {
        case .off: "Off"
        case .standard: "Standard (15 fps)"
        case .smooth: "Smooth (30 fps)"
        }
    }

    /// The option a stored rate reads as; a hand-written rate shows as the nearest one.
    init(framesPerSecond fps: Int) {
        self = Self.allCases.min { abs($0.rawValue - fps) < abs($1.rawValue - fps) } ?? .standard
    }
}

extension UserDefaults {
    /// For key-value observing; `DockSpin.key` names it.
    @objc dynamic var dockSpinFPS: Int { integer(forKey: DockSpin.key) }
}

/// Spins the cover on the Dock tile while a song plays, at the same speed as the disc in the
/// app's rows. The Dock only takes still images, so this hands it one frame after another.
/// Each frame is drawn the first time the lap reaches it and replayed from memory after that,
/// so once the first lap is done a frame costs only the handover to the Dock.
@MainActor
final class DockSpinner {
    /// Frames handed to the Dock per second, as Settings ▸ Dock has it; 0 leaves the tile still.
    static var storedFramesPerSecond: Int {
        UserDefaults.standard.object(forKey: DockSpin.key) as? Int ?? DockSpin.standard.framesPerSecond
    }

    /// The rate in use. Reduce Motion stills the tile too: the Dock is always in view at the
    /// edge of the screen, which is just where a turning picture is hardest to ignore.
    var framesPerSecond: Int { reducesMotion() ? 0 : Self.storedFramesPerSecond }

    /// Draws the tile with the cover turned by the given angle.
    typealias Renderer = @MainActor (_ angle: CGFloat) -> NSImage

    private var renderer: Renderer?
    /// The tile to show when the spin is off: the full-size still, not a frame of the lap.
    private var still: (@MainActor () -> NSImage)?
    private var frames: [NSImage?] = []
    private var index = 0
    private var timer: Timer?
    private var isPlaying = false
    /// The screen is asleep or the user switched away: nobody can see the Dock.
    private var isOutOfSight = false
    /// The Dock itself may be hidden away, waiting for the pointer.
    private let dock = DockVisibility()
    /// Hands the Dock its picture; nil puts the bundle's icon back. Tests watch it instead.
    private let presentIcon: @MainActor (NSImage?) -> Void
    private let reducesMotion: @MainActor () -> Bool
    private var rateObservation: NSKeyValueObservation?

    /// Frames in the current lap; 0 while the tile is still.
    var frameCount: Int { frames.count }

    init(
        present: @escaping @MainActor (NSImage?) -> Void = { NSApp.applicationIconImage = $0 },
        reducesMotion: @escaping @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    ) {
        presentIcon = present
        self.reducesMotion = reducesMotion
        // Settings ▸ Dock applies to the song already playing, not just the next one.
        rateObservation = UserDefaults.standard.observe(\.dockSpinFPS) { [weak self] _, _ in
            if Thread.isMainThread {
                MainActor.assumeIsolated { self?.rebuildLap() }
            } else {
                Task { @MainActor in self?.rebuildLap() }
            }
        }
        dock.onChange = { [weak self] in self?.update() }
        let center = NSWorkspace.shared.notificationCenter
        for (name, hidden) in [
            (NSWorkspace.screensDidSleepNotification, true), (NSWorkspace.screensDidWakeNotification, false),
            (NSWorkspace.sessionDidResignActiveNotification, true), (NSWorkspace.sessionDidBecomeActiveNotification, false),
        ] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.isOutOfSight = hidden; self?.update() }
            }
        }
        // Reduce Motion turned on or off in System Settings ▸ Accessibility ▸ Display.
        center.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildLap() }
        }
    }

    /// A new cover: `still` while the spin is off, otherwise a lap of `renderer`'s frames,
    /// starting over from upright.
    func show(still: @escaping @MainActor () -> NSImage, _ renderer: @escaping Renderer) {
        self.still = still
        self.renderer = renderer
        frames = []
        index = 0
        rebuildLap()
    }

    /// Back to the bundle's icon.
    func clear() {
        renderer = nil
        still = nil
        frames = []
        presentIcon(nil)
        update()
    }

    /// Lays out the lap for the current rate. A change of rate mid-song keeps the cover at the
    /// angle it had reached; turned off, the still tile comes back.
    private func rebuildLap() {
        guard renderer != nil else { return }
        let fps = framesPerSecond
        if fps <= 0 {
            frames = []
            index = 0
            if let still { presentIcon(still()) }
        } else {
            // One full turn takes 360 / degreesPerSecond seconds; a lap is that many frames.
            let count = max(1, Int((360 / SpinningArtwork.degreesPerSecond) * Double(fps)))
            guard count != frames.count else { update(); return }
            let progress = frames.isEmpty ? 0 : Double(index) / Double(frames.count)
            frames = Array(repeating: nil, count: count)
            index = Int(progress * Double(count)) % count
            present()
        }
        // The timer's interval is the old rate's; start it again at the new one.
        timer?.invalidate()
        timer = nil
        update()
    }

    func setPlaying(_ playing: Bool) {
        isPlaying = playing
        update()
    }

    private func update() {
        let fps = framesPerSecond
        let wantsToSpin = renderer != nil && isPlaying && !isOutOfSight && fps > 0 && frames.count > 1
        // Hidden, the tile rests on its current frame and carries on from it when the Dock
        // comes up.
        dock.isWatching = wantsToSpin
        let runs = wantsToSpin && dock.isInSight
        guard runs != (timer != nil) else { return }
        timer?.invalidate()
        timer = nil
        guard runs else { return }
        let timer = Timer(timeInterval: 1 / Double(fps), repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.index = (self.index + 1) % self.frames.count
                self.present()
            }
        }
        // The Dock won't mind a frame landing a few milliseconds late; the battery will mind
        // the wakeups being held to the exact beat.
        timer.tolerance = 0.2 / Double(fps)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func present() {
        guard let renderer, frames.indices.contains(index) else { return }
        if frames[index] == nil {
            frames[index] = Self.inScreenColours(renderer(CGFloat(index) / CGFloat(frames.count) * 360))
        }
        presentIcon(frames[index])
    }

    /// The Dock tile redraws every frame it's handed into the screen's colours, converting each
    /// pixel on the way. Converting once, when the frame is cached, takes that off every replay.
    private static func inScreenColours(_ image: NSImage) -> NSImage {
        guard let space = NSScreen.main?.colorSpace,
              let rep = image.representations.first as? NSBitmapImageRep,
              let converted = rep.converting(to: space, renderingIntent: .default) else { return image }
        let out = NSImage(size: image.size)
        out.addRepresentation(converted)
        return out
    }
}
