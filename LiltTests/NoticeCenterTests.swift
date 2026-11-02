import Foundation
import Testing
@testable import Lilt

/// A clock the test winds by hand: timers fire only when it is advanced past them.
@MainActor
final class ManualNoticeClock: NoticeClock {
    private(set) var now: TimeInterval = 0
    private var pending: [(id: UUID, at: TimeInterval, fire: @MainActor () -> Void)] = []

    func schedule(after delay: TimeInterval, _ fire: @escaping @MainActor () -> Void) -> NoticeTimer {
        let id = UUID()
        pending.append((id, now + delay, fire))
        return NoticeTimer { [weak self] in self?.pending.removeAll { $0.id == id } }
    }

    func advance(by seconds: TimeInterval) {
        now += seconds
        let due = pending.filter { $0.at <= now }
        pending.removeAll { $0.at <= now }
        for timer in due { timer.fire() }
    }
}

/// The panel's notices: one at a time, gone after a few seconds unless the pointer holds them,
/// and an Undo that runs once.
@MainActor
struct NoticeCenterTests {
    private let clock = ManualNoticeClock()
    private var center: NoticeCenter { NoticeCenter(clock: clock) }

    @Test func aNewNoticeReplacesTheOneUp() {
        let center = center
        center.post("Playing next: Schism")
        let first = center.current?.id
        center.post("Added to queue: Parabola")
        #expect(center.current?.message == "Added to queue: Parabola")
        #expect(center.current?.id != first)
        // The first one's countdown doesn't take the second down early.
        clock.advance(by: NoticeCenter.duration - 1)
        #expect(center.current?.message == "Added to queue: Parabola")
    }

    @Test func itDismissesItselfWhenTheTimeRunsOut() {
        let center = center
        center.post("Link copied")
        clock.advance(by: NoticeCenter.duration / 2)
        #expect(center.current != nil)
        #expect(abs(center.remainingFraction - 0.5) < 0.001)
        clock.advance(by: NoticeCenter.duration / 2)
        #expect(center.current == nil)
    }

    @Test func anActionGetsLonger() {
        let center = center
        center.post("Removed Schism", action: .undo {})
        clock.advance(by: NoticeCenter.duration)
        #expect(center.current != nil)
        clock.advance(by: NoticeCenter.actionDuration - NoticeCenter.duration)
        #expect(center.current == nil)
    }

    @Test func hoveringHoldsTheCountdown() {
        let center = center
        center.post("Added to Liked Music")
        clock.advance(by: 1)
        center.setHovering(true)
        #expect(center.isPaused)
        clock.advance(by: 60)
        #expect(center.current != nil, "a held notice stays up")
        #expect(abs(center.elapsed - 1) < 0.001)
        center.setHovering(false)
        clock.advance(by: NoticeCenter.duration - 1.5)
        #expect(center.current != nil, "the countdown picks up where it was held")
        clock.advance(by: 0.5)
        #expect(center.current == nil)
    }

    @Test func aNoticeArrivingUnderThePointerWaits() {
        let center = center
        center.post("Playing next: Schism")
        center.setHovering(true)
        center.post("Playing next: Lateralus")
        clock.advance(by: 60)
        #expect(center.current?.message == "Playing next: Lateralus")
        center.setHovering(false)
        clock.advance(by: NoticeCenter.duration)
        #expect(center.current == nil)
    }

    @Test func undoRunsOnceAndDismisses() {
        let center = center
        var undone = 0
        center.post("Playing next: Schism", action: .undo { undone += 1 })
        #expect(center.performAction(key: "x") == false, "another key isn't the action's")
        #expect(center.performAction(key: "z"))
        #expect(undone == 1)
        #expect(center.current == nil)
        #expect(center.performAction(key: "z") == false)
        #expect(undone == 1, "a second ⌘Z does nothing")
    }

    @Test func noActionNothingToPerform() {
        let center = center
        center.post("Link copied")
        #expect(center.performAction() == false)
        #expect(center.current != nil)
    }

    @Test func dismissingByIdLeavesANewerNoticeAlone() {
        let center = center
        center.post("Playing next: Schism")
        let old = center.current!.id
        center.post("Added to queue: Parabola")
        center.dismiss(old)
        #expect(center.current?.message == "Added to queue: Parabola")
        center.dismiss(center.current!.id)
        #expect(center.current == nil)
    }

    @Test func nothingIsPostedWhileNobodyCanSee() {
        var hidden = true
        let center = NoticeCenter(clock: clock, isSuppressed: { hidden })
        center.post("Link copied")
        #expect(center.current == nil)
        hidden = false
        center.post("Link copied")
        #expect(center.current != nil)
    }

    @Test func theShortcutReadsAsTheMenuWould() {
        #expect(Notice.Action.undo {}.shortcutLabel == "⌘Z")
    }

    @Test func aRefreshSaysWhetherAnythingChanged() {
        let center = NoticeCenter(clock: ManualNoticeClock())
        center.postRefresh(RefreshOutcome(old: ["Schism"], new: ["Schism"]), of: "Lateralus")
        #expect(center.current?.spoken == "Up to date Lateralus")
        center.postRefresh(RefreshOutcome(old: ["Schism"], new: ["Schism", "Parabola"]), of: "Lateralus")
        #expect(center.current?.spoken == "Refreshed Lateralus")
        center.postRefresh(.failed, of: "Lateralus")
        #expect(center.current?.spoken == "Couldn't refresh Lateralus")
        #expect(center.current?.action == nil)
    }
}
