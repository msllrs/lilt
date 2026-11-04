import SwiftUI
import Testing
@testable import Lilt

/// The platter opening and closing (Up Next, the ambience drawer) on the tweak panel's curve:
/// as shipped, Derek Briggs's ease out, or his ease-out spring. The content's animation and the
/// native frame's curve always come from the same numbers, so the window and the platter land
/// together.
@MainActor
struct PlatterMotionTests {
    private let atSpeed = { (s: TimeInterval) in s }

    @Test func theStandardIsAsShipped() {
        let style = PlatterMotionStyle.standard
        #expect(style.curve == .current)
        #expect(style.animation(scaled: atSpeed) == .spring(Spring(duration: 0.3, bounce: 0)))
        guard case .spring(let spring) = style.frameCurve(scaled: atSpeed) else {
            Issue.record("the shipped curve is a spring"); return
        }
        #expect(spring == Spring(duration: 0.3, bounce: 0))
    }

    /// cubic-bezier(0.2, 0.8, 0, 1) over 400ms: most of the travel is done by halfway, and it
    /// lands exactly at the end.
    @Test func derekBriggsEaseOut() {
        var style = PlatterMotionStyle.standard
        style.curve = .easeOut
        #expect(style.easeOutX1 == 0.2 && style.easeOutY1 == 0.8 && style.easeOutX2 == 0 && style.easeOutY2 == 1)
        #expect(style.easeOutDuration == 0.4)
        let frame = style.frameCurve(scaled: atSpeed)
        #expect(frame.duration == 0.4)
        #expect(frame.value(at: 0) == 0)
        #expect(frame.value(at: 0.2) > 0.9, "visually done in 200ms, the rest a cushion")
        #expect(frame.value(at: 0.4) == 1)
        #expect(frame.value(at: 1) == 1)
        #expect(style.animation(scaled: atSpeed) == .timingCurve(style.easeOutCurve, duration: 0.4))
    }

    /// Quick to look at, with a long tail past its duration as it rolls back into place.
    @Test func theEaseOutSpringSettlesLongAfterItLooksDone() {
        var style = PlatterMotionStyle.standard
        style.curve = .spring
        let spring = Spring(duration: style.springDuration, bounce: style.springBounce)
        #expect(style.animation(scaled: atSpeed) == .spring(spring))
        let frame = style.frameCurve(scaled: atSpeed)
        #expect(frame.duration == spring.settlingDuration)
        #expect(frame.value(at: 0.2) >= 0.88, "visually done in about 200ms")
        #expect(frame.duration > 0.6, "the tail rolls on well past it")
        let peak = stride(from: 0.0, through: frame.duration, by: 0.005).map(frame.value(at:)).max() ?? 0
        #expect(peak > 1 && peak < 1.02, "a subtle overshoot to roll back from")
        #expect(frame.value(at: frame.duration) == 1)
    }

    /// A slowed pace stretches whichever curve alike, the frame's and the content's.
    @Test func aSlowerPaceStretchesBoth() {
        var style = PlatterMotionStyle.standard
        style.curve = .easeOut
        let slow = { (s: TimeInterval) in s * 4 }
        #expect(style.frameCurve(scaled: slow).duration == 1.6)
        #expect(style.animation(scaled: slow) == .timingCurve(style.easeOutCurve, duration: 1.6))
    }

    @Test func copyValuesCarriesTheCurve() {
        let style = ArtworkStyle()
        #expect(style.swiftSnippet.contains("platterMotion = PlatterMotionStyle(curve: .current, easeOutX1: 0.20, easeOutY1: 0.80, easeOutX2: 0.00, easeOutY2: 1.00, easeOutDuration: 0.40, springDuration: 0.40, springBounce: 0.16)"))
    }
}
