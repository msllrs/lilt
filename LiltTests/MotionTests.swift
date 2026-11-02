import AppKit
import SwiftUI
import Testing
@testable import Lilt

/// Motion tokens are built from the current pace: the tweak panel's Animation speed stretches
/// every one alike, and the native frame steps along a curve stretched by the same factor as
/// the content it reveals, so the two stay in phase in slow motion. Each test resolves tokens at
/// a pace of its own (a task-local), leaving the live settings to suites running alongside.
/// Under Reduce Motion each token becomes what it declares: travel lands at once, fades stay.
@MainActor
struct MotionTests {
    private static func at<T>(_ speed: Double, reducing: Bool = false, _ body: () throws -> T) rethrows -> T {
        try MotionPace.$override.withValue(MotionPace(speed: speed, reducesMotion: reducing), operation: body)
    }

    // MARK: Scaling

    @Test func aPaceStretchesSecondsByTheInverseOfItsSpeed() {
        #expect(MotionPace(speed: 1).scaled(0.22) == 0.22)
        #expect(MotionPace(speed: 0.5).scaled(0.22) == 0.44)
        #expect(abs(MotionPace(speed: 0.1).scaled(0.18) - 1.8) < 1e-12)
    }

    @Test func slowedTokensRunAsManyTimesLonger() {
        Self.at(0.25) {
            #expect(Theme.Motion.quick == .easeOut(duration: 0.72))
            #expect(Theme.Motion.standard == .snappy(duration: 1.12))
            #expect(Theme.Motion.settle == .smooth(duration: 1.2))
            #expect(Theme.Motion.bounce == .spring(duration: 1.68, bounce: 0.22))
            #expect(Theme.Motion.cast == .easeInOut(duration: 3.2))
            #expect(Theme.Motion.frameDuration == 0.88)
            #expect(Theme.Motion.frame == .easeOut(duration: 0.88))
            #expect(Theme.Motion.queueSpring == Spring(duration: 1.2, bounce: 0))
            #expect(Theme.Motion.queue == .spring(Spring(duration: 1.2, bounce: 0)))
            #expect(Theme.Motion.pageEnter == .easeOut(duration: 0.8))
            #expect(Theme.Motion.pageExit == .easeOut(duration: 0.48))
            #expect(Theme.Motion.symbol == .snappy(duration: 0.88))
            #expect(Theme.Motion.press == .easeOut(duration: 0.32))
            #expect(Theme.Motion.release == .spring(duration: 1.2, bounce: 0.35))
            #expect(Theme.Motion.rest == .easeInOut(duration: 4.8))
            #expect(Theme.Motion.wake == .easeOut(duration: 0.48))
        }
    }

    @Test func theSpeedIsHeldBetweenATenthAndDesigned() {
        let settings = MotionSettings()
        settings.speed = 0.01
        #expect(settings.speed == 0.1)
        settings.speed = 3
        #expect(settings.speed == 1)
        settings.speed = 0.25
        #expect(settings.pace == MotionPace(speed: 0.25))
    }

    // MARK: The native frame

    @Test func theFrameCurvesStretchWithTheSpeed() {
        let frame = Self.at(1) { Theme.Motion.frameCurve }
        let queue = Self.at(1) { Theme.Motion.queueCurve }
        let disc = Self.at(1) { Theme.Motion.standardCurve }
        for speed in [0.1, 0.25, 0.5] {
            let slowFrame = Self.at(speed) { Theme.Motion.frameCurve }
            let slowQueue = Self.at(speed) { Theme.Motion.queueCurve }
            let slowDisc = Self.at(speed) { Theme.Motion.standardCurve }
            #expect(abs(slowFrame.duration - frame.duration / speed) < 1e-9)
            // A spring runs to its settling time, which SwiftUI measures against a fixed
            // threshold, so it lengthens a little less than the spring itself (0.5s at 1×,
            // 4.5s rather than 5s at 0.1×); the curve up to there is the same one slowed.
            #expect(slowQueue.duration > queue.duration / speed * 0.85 && slowQueue.duration <= queue.duration / speed + 1e-9)
            #expect(slowDisc.duration > disc.duration / speed * 0.75 && slowDisc.duration <= disc.duration / speed + 1e-9)
            // The same curve in slow motion: a step taken `t` in at 1× is where the slowed
            // curve is at `t / speed`, so the window's stepping slows with its duration.
            for t in stride(from: 0.0, through: frame.duration, by: 0.02) {
                #expect(abs(slowFrame.value(at: t / speed) - frame.value(at: t)) < 1e-9)
            }
            for t in stride(from: 0.0, to: min(queue.duration, slowQueue.duration * speed), by: 0.02) {
                #expect(abs(slowQueue.value(at: t / speed) - queue.value(at: t)) < 1e-6)
            }
        }
    }

    /// The window and the list it reveals ride one spring: the content's animation is built
    /// from the very spring the frame steps along, at any speed.
    @Test func theQueueAndTheWindowShareOneSpringWhenSlowed() {
        Self.at(0.25) {
            guard case .spring(let spring) = Theme.Motion.queueCurve else {
                Issue.record("the queue's frame curve is not a spring")
                return
            }
            #expect(spring == Theme.Motion.queueSpring)
            guard case .easeOut(let duration) = Theme.Motion.frameCurve else {
                Issue.record("the frame curve is not an ease-out")
                return
            }
            #expect(Theme.Motion.frame == .easeOut(duration: duration))
        }
    }

    @Test func theWindowsFrameAnimationLastsAsLongAsTheSlowedCurve() {
        let window = PanelWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 320, height: 600))
        defer { window.applyNativeCornerRadius(Theme.Radius.window) }
        let target = NSRect(x: -10_000, y: -10_000, width: 320, height: 160)
        for speed in [1, 0.5, 0.1] {
            let curve = Self.at(speed) { Theme.Motion.frameCurve }
            window.animateNativeFrame(to: target, cornerRadius: Theme.Radius.window, curve: curve) {}
            #expect(window.frameAnimationDuration.map { abs($0 - 0.22 / speed) < 1e-9 } == true)
            // Cutting it short settles it.
            window.applyNativeCornerRadius(Theme.Radius.window)
            #expect(window.frameAnimationDuration == nil)
        }
    }

    // MARK: Reduce Motion

    @Test func underReduceMotionTravelLandsAtOnceAndFadesStay() {
        Self.at(1, reducing: true) {
            // Kept: fades, colour, glyphs swapping in place, a button giving under the pointer.
            #expect(Theme.Motion.quick == .easeOut(duration: 0.18))
            #expect(Theme.Motion.standard == .snappy(duration: 0.28))
            #expect(Theme.Motion.cast == .easeInOut(duration: 0.8))
            #expect(Theme.Motion.symbol == .snappy(duration: 0.22))
            #expect(Theme.Motion.press == .easeOut(duration: 0.08))
            #expect(Theme.Motion.release == .spring(duration: 0.3, bounce: 0.35))
            // The page hand-off keeps its fades but slides nowhere: a crossfade.
            #expect(Theme.Motion.pageEnter == .easeOut(duration: 0.2))
            #expect(Theme.Motion.pageExit == .easeOut(duration: 0.12))
            #expect(Theme.Motion.pageTravel == 0)
            // Resting stays a fade, a short crossfade rather than the slow settle; waking is
            // already quick.
            #expect(Theme.Motion.rest == .easeOut(duration: 0.2))
            #expect(Theme.Motion.wake == .easeOut(duration: 0.12))
            // Instant: Up Next shuffling, a container's overshoot, the mini player's frame, the
            // queue opening, closing or let go after a pull.
            #expect(Theme.Motion.settle == nil)
            #expect(Theme.Motion.bounce == nil)
            #expect(Theme.Motion.frame == nil)
            #expect(Theme.Motion.queue == nil)
            // The curves the window and the disc step along take no time and start at the end.
            for curve in [Theme.Motion.frameCurve, Theme.Motion.queueCurve, Theme.Motion.standardCurve] {
                #expect(curve.duration == 0)
                #expect(curve.value(at: 0) == 1)
            }
        }
    }

    @Test func withoutReduceMotionPagesTravel() {
        #expect(Self.at(1) { Theme.Motion.pageTravel } == 20)
        #expect(Self.at(0.1) { Theme.Motion.pageTravel } == 20)
    }

    @Test func keptTokensStillSlowUnderReduceMotion() {
        Self.at(0.5, reducing: true) {
            #expect(Theme.Motion.quick == .easeOut(duration: 0.36))
            #expect(Theme.Motion.pageEnter == .easeOut(duration: 0.4))
            #expect(Theme.Motion.rest == .easeOut(duration: 0.4))
            #expect(Theme.Motion.frameCurve.duration == 0)
        }
    }

    @Test func theForcedOverrideTurnsReduceMotionOn() {
        let settings = MotionSettings()
        settings.forcesReduceMotion = true
        #expect(settings.pace.reducesMotion)
        settings.forcesReduceMotion = false
        #expect(settings.pace.reducesMotion == settings.systemReducesMotion)
    }

    /// The mini player's frame under Reduce Motion: snapped there, no display link, done.
    @Test func underReduceMotionTheWindowSnaps() {
        let window = PanelWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 320, height: 600))
        let target = NSRect(x: -10_000, y: -10_000, width: 320, height: 160)
        let curve = Self.at(1, reducing: true) { Theme.Motion.frameCurve }
        var landed = false
        window.animateNativeFrame(to: target, cornerRadius: Theme.Radius.window, curve: curve) { landed = true }
        #expect(landed)
        #expect(window.frameAnimationDuration == nil)
        #expect(window.frame.height == target.height)
    }

    /// The disc turning upright under Reduce Motion is there at once, with no settle.
    @Test func underReduceMotionTheDiscIsUprightAtOnce() {
        let view = SpinningPictureView(frame: NSRect(x: 0, y: 0, width: 40, height: 40))
        let dps = SpinningArtwork.degreesPerSecond
        view.apply(ArtworkSpin(baseAngle: 100, resumedAt: nil, degreesPerSecond: dps, paused: true))
        Self.at(1, reducing: true) {
            view.apply(ArtworkSpin(baseAngle: 0, resumedAt: nil, degreesPerSecond: dps, paused: true))
        }
        #expect(view.picture.animation(forKey: SpinningPictureView.spinKey) == nil)
        #expect(abs(view.displayedDegrees) < 1e-9 || abs(view.displayedDegrees - 360) < 1e-9)
    }

    // MARK: Regression guard

    /// At designed speed every token is exactly the curve it was before tokens were scaled.
    @Test func atDesignedSpeedTokensAreTheirDesignedCurves() {
        Self.at(1) {
            #expect(Theme.Motion.quick == .easeOut(duration: 0.18))
            #expect(Theme.Motion.standard == .snappy(duration: 0.28))
            #expect(Theme.Motion.settle == .smooth(duration: 0.3))
            #expect(Theme.Motion.bounce == .spring(duration: 0.42, bounce: 0.22))
            #expect(Theme.Motion.cast == .easeInOut(duration: 0.8))
            #expect(Theme.Motion.frameDuration == 0.22)
            #expect(Theme.Motion.frame == .easeOut(duration: 0.22))
            #expect(Theme.Motion.queueSpring == Spring(duration: 0.3, bounce: 0))
            #expect(Theme.Motion.queue == .spring(Spring(duration: 0.3, bounce: 0)))
            #expect(Theme.Motion.pageEnter == .easeOut(duration: 0.2))
            #expect(Theme.Motion.pageExit == .easeOut(duration: 0.12))
            #expect(Theme.Motion.symbol == .snappy(duration: 0.22))
            #expect(Theme.Motion.press == .easeOut(duration: 0.08))
            #expect(Theme.Motion.release == .spring(duration: 0.3, bounce: 0.35))
            #expect(Theme.Motion.rest == .easeInOut(duration: 1.2))
            #expect(Theme.Motion.wake == .easeOut(duration: 0.12))
            #expect(Theme.Motion.frameCurve.duration == 0.22)
            #expect(Theme.Motion.queueCurve.duration == Spring(duration: 0.3, bounce: 0).settlingDuration)
            #expect(Theme.Motion.standardCurve.duration == Spring.snappy(duration: 0.28).settlingDuration)
        }
    }
}
