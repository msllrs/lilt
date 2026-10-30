import AppKit

/// Spins the cover on the Dock tile while a song plays, at the same speed as the disc in the
/// app's rows. The Dock only takes still images, so this hands it one frame after another.
/// Each frame is drawn the first time the lap reaches it and replayed from memory after that,
/// so once the first lap is done a frame costs only the handover to the Dock.
@MainActor
final class DockSpinner {
    /// Frames handed to the Dock per second; 0 leaves the tile still. 8 looked steppy, 15 holds
    /// up at ordinary Dock sizes. Read when a song loads:
    /// `defaults write com.msllrs.Lilt dockSpinFPS -int 12`.
    static var framesPerSecond: Int {
        UserDefaults.standard.object(forKey: "dockSpinFPS") as? Int ?? 15
    }

    /// Draws the tile with the cover turned by the given angle.
    typealias Renderer = @MainActor (_ angle: CGFloat) -> NSImage

    private var renderer: Renderer?
    private var frames: [NSImage?] = []
    private var index = 0
    private var timer: Timer?
    private var isPlaying = false
    /// The screen is asleep or the user switched away: nobody can see the Dock.
    private var isOutOfSight = false

    init() {
        let center = NSWorkspace.shared.notificationCenter
        for (name, hidden) in [
            (NSWorkspace.screensDidSleepNotification, true), (NSWorkspace.screensDidWakeNotification, false),
            (NSWorkspace.sessionDidResignActiveNotification, true), (NSWorkspace.sessionDidBecomeActiveNotification, false),
        ] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.isOutOfSight = hidden; self?.update() }
            }
        }
    }

    /// A new cover. The lap starts over from upright.
    func show(_ renderer: @escaping Renderer) {
        let fps = Self.framesPerSecond
        self.renderer = renderer
        // One full turn takes 360 / degreesPerSecond seconds; a lap is that many frames.
        frames = Array(repeating: nil, count: max(1, Int((360 / SpinningArtwork.degreesPerSecond) * Double(fps))))
        index = 0
        present()
        update()
    }

    /// Back to the bundle's icon.
    func clear() {
        renderer = nil
        frames = []
        update()
    }

    func setPlaying(_ playing: Bool) {
        isPlaying = playing
        update()
    }

    private func update() {
        let fps = Self.framesPerSecond
        let runs = renderer != nil && isPlaying && !isOutOfSight && fps > 0 && frames.count > 1
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
        NSApp.applicationIconImage = frames[index]
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
