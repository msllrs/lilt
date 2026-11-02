import Foundation
import Observation

/// A short confirmation inside the panel ("Queued Schism"), with an optional action
/// such as Undo. Shown one at a time by `NoticeCenter`; drawn by `NoticeHost`.
struct Notice: Identifiable {
    enum Icon: Equatable {
        /// An SF Symbol, for actions about the song rather than a cover (Like, Copy Link).
        case symbol(String)
        /// A cover thumbnail.
        case artwork(URL?)
    }

    /// The notice's one button. Its key, with ⌘, performs it while the notice is up.
    struct Action {
        var title: String
        var key: Character
        var perform: @MainActor () -> Void

        /// ⌘Z, as Undo is everywhere else on the Mac.
        static func undo(_ perform: @escaping @MainActor () -> Void) -> Action {
            Action(title: "Undo", key: "z", perform: perform)
        }

        /// The shortcut as the button shows it.
        var shortcutLabel: String { "⌘" + String(key).uppercased() }
    }

    let id = UUID()
    /// What it acted on: a song, album or playlist title.
    var message: String
    /// What happened, in a word or two ("Liked", "Queued"), set before the title in a heavier
    /// weight. The icon beside it says what kind of thing happened, so the word can stay short.
    var label: String? = nil
    var icon: Icon?
    var action: Action?

    /// The whole line, for VoiceOver and tests.
    var spoken: String { [label, message].compactMap { $0 }.joined(separator: " ") }
}

/// When a notice's countdown runs out: the real clock in the app, a hand-wound one in tests.
@MainActor
protocol NoticeClock: AnyObject {
    /// Seconds on a monotonic clock.
    var now: TimeInterval { get }
    /// Calls `fire` after `delay` seconds unless the returned timer is cancelled first.
    func schedule(after delay: TimeInterval, _ fire: @escaping @MainActor () -> Void) -> NoticeTimer
}

/// A scheduled firing that can be called off.
@MainActor
final class NoticeTimer {
    private let onCancel: @MainActor () -> Void
    init(cancel: @escaping @MainActor () -> Void) { onCancel = cancel }
    func cancel() { onCancel() }
}

@MainActor
final class SystemNoticeClock: NoticeClock {
    var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    func schedule(after delay: TimeInterval, _ fire: @escaping @MainActor () -> Void) -> NoticeTimer {
        let task = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            if !Task.isCancelled { fire() }
        }
        return NoticeTimer { task.cancel() }
    }
}

/// The panel's one notice at a time. A new one replaces whatever is up; each dismisses itself
/// after a few seconds, the countdown holding while the pointer rests on it.
@MainActor
@Observable
final class NoticeCenter {
    /// How long a notice stays up.
    static let duration: TimeInterval = 4
    /// Longer when it offers an action, so there's time to reach for it.
    static let actionDuration: TimeInterval = 6

    private(set) var current: Notice?
    /// The countdown is held (the pointer is on the notice).
    private(set) var isPaused = false
    /// How long the current notice lasts in all.
    private(set) var lifetime: TimeInterval = 0

    /// True when nobody would see a notice (the panel is out of sight, or the mini player has
    /// no room for one); posts are dropped. Wired by the app.
    @ObservationIgnored var isSuppressed: @MainActor () -> Bool

    @ObservationIgnored private let clock: NoticeClock
    @ObservationIgnored private var timer: NoticeTimer?
    @ObservationIgnored private var isHovering = false
    /// Time counted down before the running stretch began, and when that stretch began.
    @ObservationIgnored private var elapsedBefore: TimeInterval = 0
    @ObservationIgnored private var runningSince: TimeInterval = 0

    init(clock: NoticeClock? = nil, isSuppressed: @escaping @MainActor () -> Bool = { false }) {
        self.clock = clock ?? SystemNoticeClock()
        self.isSuppressed = isSuppressed
    }

    /// Shows `notice` in place of the current one.
    func post(_ notice: Notice) {
        guard !isSuppressed() else { return }
        timer?.cancel()
        timer = nil
        current = notice
        lifetime = notice.action == nil ? Self.duration : Self.actionDuration
        elapsedBefore = 0
        runningSince = clock.now
        // A notice arriving under a resting pointer waits for it to leave.
        isPaused = isHovering
        if !isPaused { schedule() }
    }

    func post(_ message: String, label: String? = nil, icon: Notice.Icon? = nil, action: Notice.Action? = nil) {
        post(Notice(message: message, label: label, icon: icon, action: action))
    }

    /// Seconds counted down so far.
    var elapsed: TimeInterval { elapsedBefore + (isPaused ? 0 : clock.now - runningSince) }

    /// What's left of the countdown, 1 at the start and 0 when it runs out.
    var remainingFraction: Double {
        guard current != nil, lifetime > 0 else { return 0 }
        return min(max(1 - elapsed / lifetime, 0), 1)
    }

    /// The pointer resting on the notice holds the countdown; leaving resumes it.
    func setHovering(_ hovering: Bool) {
        guard hovering != isHovering else { return }
        isHovering = hovering
        guard current != nil else { return }
        if hovering {
            elapsedBefore = elapsed
            isPaused = true
            timer?.cancel()
            timer = nil
        } else {
            runningSince = clock.now
            isPaused = false
            schedule()
        }
    }

    /// Takes the notice down. With an id, only if that notice is still the one up.
    func dismiss(_ id: Notice.ID? = nil) {
        guard let current, id == nil || current.id == id else { return }
        timer?.cancel()
        timer = nil
        self.current = nil
        isPaused = false
        // The view under the pointer goes with it, and won't report the pointer leaving.
        isHovering = false
    }

    /// Runs the notice's action, once, and takes the notice down. False when there is no
    /// notice, no action, or the action has another key.
    @discardableResult
    func performAction(key: Character? = nil) -> Bool {
        guard let action = current?.action, key == nil || key == action.key else { return false }
        dismiss()
        action.perform()
        return true
    }

    private func schedule() {
        guard let id = current?.id else { return }
        timer = clock.schedule(after: max(0, lifetime - elapsedBefore)) { [weak self] in
            guard let self, self.current?.id == id, !self.isPaused else { return }
            self.dismiss()
        }
    }
}
