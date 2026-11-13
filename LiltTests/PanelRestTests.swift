import Foundation
import Testing
@testable import Lilt

/// Fade when not in use: when the panel rests and when it wakes, on a hand-wound clock.
@MainActor
struct PanelRestTests {
    /// A clock that only moves when told to; waits fire as it passes their deadline.
    @MainActor
    final class ManualClock {
        private(set) var now: Duration = .zero
        private var waits: [(id: Int, deadline: Duration, fire: @MainActor () -> Void)] = []
        private var nextID = 0
        var pending: Int { waits.count }

        func schedule(_ after: Duration, _ fire: @escaping @MainActor () -> Void) -> () -> Void {
            let id = nextID
            nextID += 1
            waits.append((id, now + after, fire))
            return { [weak self] in self?.waits.removeAll { $0.id == id } }
        }

        func advance(by step: Duration) {
            now += step
            let due = waits.filter { $0.deadline <= now }
            waits.removeAll { $0.deadline <= now }
            for wait in due { wait.fire() }
        }
    }

    private let clock = ManualClock()

    private func makeRest(available: Bool = true, pointerInside: Bool = true) -> PanelRest {
        let clock = clock
        let rest = PanelRest(schedule: { after, fire in clock.schedule(after, fire) }, isButtonDown: { false }, pointerIsInside: { pointerInside })
        rest.setAvailable(available)
        return rest
    }

    // MARK: Resting

    @Test func restsAfterTheDelayWithThePointerAway() {
        let rest = makeRest()
        rest.pointerExited()
        clock.advance(by: .milliseconds(2_900))
        #expect(!rest.isResting)
        clock.advance(by: .milliseconds(100))
        #expect(rest.isResting)
    }

    @Test func doesNotRestWithThePointerInside() {
        let rest = makeRest()
        clock.advance(by: .seconds(60))
        #expect(!rest.isResting)
        #expect(clock.pending == 0, "nothing waits while the pointer is over the panel")
    }

    @Test func thePointerComingBackBeforeTheDelayCancelsTheWait() {
        let rest = makeRest()
        rest.pointerExited()
        clock.advance(by: .seconds(2))
        rest.pointerEntered()
        clock.advance(by: .seconds(10))
        #expect(!rest.isResting)
        #expect(clock.pending == 0)
    }

    /// One wait at a time: leaving again starts it over rather than adding a second.
    @Test func thereIsOnlyEverOneWait() {
        let rest = makeRest()
        rest.pointerExited()
        rest.pointerEntered()
        rest.pointerExited()
        rest.keyPressed()
        #expect(clock.pending == 1)
        clock.advance(by: .seconds(3))
        #expect(rest.isResting)
        #expect(clock.pending == 0)
    }

    /// Launched with the pointer elsewhere, no exit ever arrives; where it is is asked instead.
    @Test func startsCountingWhenItBecomesAvailableWithThePointerAway() {
        let rest = makeRest(available: false, pointerInside: false)
        clock.advance(by: .seconds(10))
        #expect(!rest.isResting)
        rest.setAvailable(true)
        clock.advance(by: .seconds(3))
        #expect(rest.isResting)
    }

    // MARK: Waking

    @Test func wakesTheMomentThePointerEnters() {
        let rest = makeRest()
        rest.pointerExited()
        clock.advance(by: .seconds(3))
        #expect(rest.isResting)
        rest.pointerEntered()
        #expect(!rest.isResting)
    }

    @Test func aKeyWakesItAndTheWaitStartsOver() {
        let rest = makeRest()
        rest.pointerExited()
        clock.advance(by: .seconds(3))
        rest.keyPressed()
        #expect(!rest.isResting)
        clock.advance(by: .seconds(2))
        rest.keyPressed()
        clock.advance(by: .seconds(2))
        #expect(!rest.isResting, "each key starts the wait again")
        clock.advance(by: .seconds(1))
        #expect(rest.isResting)
    }

    // MARK: Holds

    @Test func neverRestsWhileAMenuIsOpen() {
        let rest = makeRest()
        rest.pointerExited()
        rest.setHold(.menu, true)
        clock.advance(by: .seconds(30))
        #expect(!rest.isResting)
        rest.setHold(.menu, false)
        clock.advance(by: .seconds(3))
        #expect(rest.isResting, "the wait starts over once the menu closes")
    }

    @Test func aMenuOpeningWakesIt() {
        let rest = makeRest()
        rest.pointerExited()
        clock.advance(by: .seconds(3))
        rest.setHold(.menu, true)
        #expect(!rest.isResting)
    }

    @Test func neverRestsWhileTyping() {
        let rest = makeRest()
        rest.pointerExited()
        rest.setHold(.typing, true)
        clock.advance(by: .seconds(30))
        #expect(!rest.isResting)
        rest.setHold(.typing, false)
        clock.advance(by: .seconds(3))
        #expect(rest.isResting)
    }

    @Test func bothHoldsMustLetGo() {
        let rest = makeRest()
        rest.pointerExited()
        rest.setHold(.typing, true)
        rest.setHold(.menu, true)
        rest.setHold(.menu, false)
        clock.advance(by: .seconds(30))
        #expect(!rest.isResting)
    }

    /// A drag carried out of the panel: still held when the wait runs out, so it waits again.
    @Test func neverRestsUnderAHeldButton() {
        var down = true
        let clock = clock
        let rest = PanelRest(schedule: { clock.schedule($0, $1) }, isButtonDown: { down }, pointerIsInside: { true })
        rest.setAvailable(true)
        rest.pointerExited()
        clock.advance(by: .seconds(3))
        #expect(!rest.isResting)
        #expect(clock.pending == 1)
        down = false
        clock.advance(by: .seconds(3))
        #expect(rest.isResting)
    }

    // MARK: Where it applies

    /// Mini has no column, a hidden panel needs nothing, and with the setting off it never rests.
    @Test func neverRestsWhenUnavailable() {
        let rest = makeRest(available: false)
        rest.pointerExited()
        clock.advance(by: .seconds(30))
        #expect(!rest.isResting)
        #expect(clock.pending == 0)
    }

    /// Going to mini (or hiding the panel) while resting wakes it, so it comes back awake.
    @Test func becomingUnavailableWakesIt() {
        let rest = makeRest()
        rest.pointerExited()
        clock.advance(by: .seconds(3))
        #expect(rest.isResting)
        rest.setAvailable(false)
        #expect(!rest.isResting)
        #expect(clock.pending == 0)
    }

    @Test func theSettingIsOffByDefault() throws {
        #expect(PanelRest.enabledByDefault == false)
        let suite = "PanelRestTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(!PanelRest.isEnabled(in: defaults))
        defaults.set(true, forKey: PanelRest.enabledKey)
        #expect(PanelRest.isEnabled(in: defaults))
    }

    // MARK: The pointer

    /// Rows show their lengths only with the pointer over the panel, so it's followed with the
    /// setting off too.
    @Test func thePointerIsFollowedWhetherOrNotThePanelCanRest() {
        let rest = makeRest(available: false)
        #expect(rest.isPointerInside)
        rest.pointerExited()
        #expect(!rest.isPointerInside)
        rest.pointerEntered()
        #expect(rest.isPointerInside)
        #expect(clock.pending == 0, "nothing waits to rest")
    }
}
