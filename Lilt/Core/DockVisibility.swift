import AppKit

/// Whether the Dock can be seen, so the spinning tile can rest while it can't. macOS doesn't
/// say, so this reads two signs: a Dock kept shown takes room from the screen's visible frame,
/// and a Dock that hides itself comes up when the pointer reaches the screen's edge.
@MainActor
final class DockVisibility {
    /// Called when `isInSight` changes.
    var onChange: (() -> Void)?

    /// Set while something wants to know; the pointer is only watched then.
    var isWatching = false {
        didSet { if isWatching != oldValue { refresh() } }
    }

    private(set) var isInSight = true
    private var isKeptShown = DockVisibility.isKeptShownOnAnyScreen()
    private var isUp = false
    private var poll: Timer?

    /// How close to the edge the pointer must be before the Dock comes up.
    private nonisolated static let edgeTrigger: CGFloat = 2
    /// How far from the edge the Dock reaches: the largest tile and its padding, with room for
    /// magnification. Past this, the pointer has left it and the Dock slides away.
    private nonisolated static let dockReach: CGFloat = 160
    /// Pointer and ⌘ checks per second. Ten keeps up with the Dock's own slide in, and with the
    /// beat ⌘-Tab takes to bring its switcher up.
    private static let checksPerSecond: Double = 10

    init() {
        // Turning hiding on or off (⌥⌘D, Settings) changes the screens' visible frames.
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isKeptShown = Self.isKeptShownOnAnyScreen()
                self.refresh()
            }
        }
    }

    /// A Dock kept shown leaves a gap along the bottom, the left or the right of the visible
    /// frame. The top is the menu bar's.
    nonisolated static func isKeptShown(frame: NSRect, visibleFrame: NSRect) -> Bool {
        visibleFrame.minY > frame.minY || visibleFrame.minX > frame.minX || visibleFrame.maxX < frame.maxX
    }

    /// The Dock comes up when the pointer reaches the bottom, left or right edge, and stays up
    /// while the pointer is over it.
    nonisolated static func bringsDockUp(pointer: CGPoint, in screen: NSRect, wasUp: Bool) -> Bool {
        let distance = min(pointer.y - screen.minY, pointer.x - screen.minX, screen.maxX - 1 - pointer.x)
        return distance <= (wasUp ? dockReach : edgeTrigger)
    }

    /// ⌘-Tab's switcher draws the tile too, with the Dock still hidden. macOS doesn't say when
    /// the switcher is up, but it's only up while ⌘ is held, so ⌘ counts as in sight. Holding ⌘
    /// for any other shortcut spins the tile for that moment too, which does no harm.
    nonisolated static func isInSight(dockUp: Bool, modifiers: NSEvent.ModifierFlags) -> Bool {
        dockUp || modifiers.intersection(.deviceIndependentFlagsMask).contains(.command)
    }

    private static func isKeptShownOnAnyScreen() -> Bool {
        NSScreen.screens.contains { isKeptShown(frame: $0.frame, visibleFrame: $0.visibleFrame) }
    }

    private func refresh() {
        guard isWatching, !isKeptShown else {
            poll?.invalidate()
            poll = nil
            isUp = false
            set(inSight: true)
            return
        }
        if poll == nil {
            let timer = Timer(timeInterval: 1 / Self.checksPerSecond, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkPointer() }
            }
            timer.tolerance = 0.5 / Self.checksPerSecond
            RunLoop.main.add(timer, forMode: .common)
            poll = timer
        }
        checkPointer()
    }

    private func checkPointer() {
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) }) else { return }
        isUp = Self.bringsDockUp(pointer: pointer, in: screen.frame, wasUp: isUp)
        // The class property reads the keyboard's state without Accessibility permission, which
        // a global key monitor would need.
        set(inSight: Self.isInSight(dockUp: isUp, modifiers: NSEvent.modifierFlags))
    }

    private func set(inSight: Bool) {
        guard inSight != isInSight else { return }
        isInSight = inSight
        onChange?()
    }
}
