import AppKit
import Observation

/// Settings ▸ Appearance ▸ Fade when not in use: once the pointer has been away from the panel
/// for `delay` and nothing in it is being used, the browse column recedes and the panel sits
/// quietly on the screen edge; the platter stays as it is.
///
/// The rule. The panel rests when all of these hold for `delay` without a break:
/// - the setting is on, the panel is expanded (mini has no column) and on screen;
/// - the pointer is outside the panel;
/// - no key has been pressed in it (each key press wakes it and starts the wait again);
/// - nobody is typing in the search field: a key pressed while the field has the keyboard holds
///   the panel awake until the field gives up focus or the panel stops being key. Focus alone
///   doesn't, since the field takes it every time the panel becomes key;
/// - no menu is open (a row's menu, a context menu, the menu bar);
/// - no mouse button is held (a drag, a resize, the grab handle pulled past the edge).
/// It wakes at once on the pointer entering, a key, a menu opening, or the panel coming back
/// into sight; nothing here polls. The wait is one cancellable task, started on a change and
/// cancelled on the next.
@MainActor
@Observable
final class PanelRest {
    /// The setting, off unless turned on.
    static let enabledKey = "fadesWhenNotInUse"
    static let enabledByDefault = false
    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: enabledKey) as? Bool ?? enabledByDefault
    }

    /// How long the pointer stays away before the panel rests.
    static let delay: Duration = .seconds(3)

    /// The browse column is receding. Changes only on the transitions, so the views reading it
    /// re-render twice per rest, never in between.
    private(set) var isResting = false

    /// What holds the panel awake whatever the pointer does.
    enum Hold: Hashable { case typing, menu }

    /// Starts a wait of `after` that calls `fire` when it runs out; the returned closure cancels
    /// it. A task in the app, a hand-wound clock in tests.
    typealias Schedule = @MainActor (_ after: Duration, _ fire: @escaping @MainActor () -> Void) -> (() -> Void)

    @ObservationIgnored private let schedule: Schedule
    /// Whether a mouse button is down, asked only when a wait runs out.
    @ObservationIgnored var isButtonDown: () -> Bool
    /// Where the pointer is, asked when the panel becomes able to rest: a hidden window gets no
    /// tracking events, so what it last heard may be stale.
    @ObservationIgnored var pointerIsInside: () -> Bool?

    @ObservationIgnored private var isAvailable = false
    @ObservationIgnored private(set) var isPointerInside = true
    @ObservationIgnored private(set) var holds: Set<Hold> = []
    @ObservationIgnored private var cancelWait: (() -> Void)?

    /// Whether a wait is under way (for tests).
    var isWaiting: Bool { cancelWait != nil }

    init(
        schedule: @escaping Schedule = PanelRest.taskSchedule,
        isButtonDown: @escaping () -> Bool = { NSEvent.pressedMouseButtons != 0 },
        pointerIsInside: @escaping () -> Bool? = { nil }
    ) {
        self.schedule = schedule
        self.isButtonDown = isButtonDown
        self.pointerIsInside = pointerIsInside
    }

    /// One task that sleeps; cancelling it ends the sleep without firing.
    static let taskSchedule: Schedule = { after, fire in
        let task = Task { @MainActor in
            do { try await Task.sleep(for: after) } catch { return }
            fire()
        }
        return { task.cancel() }
    }

    // MARK: Inputs

    /// The setting is on, the panel expanded and on screen. Becoming available starts awake;
    /// becoming unavailable wakes and stops waiting.
    func setAvailable(_ available: Bool) {
        guard available != isAvailable else { return }
        isAvailable = available
        if available, let inside = pointerIsInside() { isPointerInside = inside }
        wake()
        armIfIdle()
    }

    func pointerEntered() {
        isPointerInside = true
        wake()
    }

    func pointerExited() {
        isPointerInside = false
        armIfIdle()
    }

    /// A key pressed in the panel: back at once, and the wait starts over.
    func keyPressed() {
        wake()
        armIfIdle()
    }

    func setHold(_ hold: Hold, _ on: Bool) {
        if on {
            holds.insert(hold)
            wake()
        } else if holds.remove(hold) != nil {
            armIfIdle()
        }
    }

    // MARK: The wait

    private func wake() {
        cancelWait?()
        cancelWait = nil
        if isResting { isResting = false }
    }

    private var canRest: Bool { isAvailable && !isPointerInside && holds.isEmpty }

    /// Starts the wait over if nothing is in use.
    private func armIfIdle() {
        cancelWait?()
        cancelWait = nil
        guard canRest, !isResting else { return }
        cancelWait = schedule(Self.delay) { [weak self] in self?.waitRanOut() }
    }

    private func waitRanOut() {
        cancelWait = nil
        guard canRest else { return }
        // A drag or a press that began in the panel may have carried the pointer out; wait
        // another round rather than fade under it.
        if isButtonDown() {
            armIfIdle()
            return
        }
        isResting = true
    }
}
