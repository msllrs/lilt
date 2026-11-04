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

    /// Derek's ease-out spring: a second long, but most of the way there by 200ms on the ease
    /// out, past the end by the overshoot at the approach, then a roll back slower than the
    /// approach, landing exactly at the end. One function for the window and the content.
    @Test func theEaseOutSpringCushionsPastTheEndAndRollsBack() {
        var style = PlatterMotionStyle.standard
        style.curve = .easeOutSpring
        #expect(style.springDuration == 1 && style.springApproach == 0.4 && style.springOvershoot == 0.024)
        let spring = style.easeOutSpring(scaled: atSpeed)
        #expect(style.animation(scaled: atSpeed) == Animation(spring))
        guard case .easeOutSpring(let frameSpring) = style.frameCurve(scaled: atSpeed) else {
            Issue.record("the window rides the same curve"); return
        }
        #expect(frameSpring == spring)
        let frame = style.frameCurve(scaled: atSpeed)
        #expect(frame.duration == 1)
        #expect(frame.value(at: 0) == 0)
        #expect(frame.value(at: 0.2) > 0.9, "visually there in about 200ms")
        #expect(abs(frame.value(at: 0.4) - 1.024) < 1e-9, "the cushion: past the end by the overshoot")
        let samples = stride(from: 0.4, through: 1.0, by: 0.02).map(frame.value(at:))
        #expect(zip(samples, samples.dropFirst()).allSatisfy { $0 >= $1 }, "then only rolls back")
        #expect(frame.value(at: 0.7) > 1 && frame.value(at: 0.7) < 1.024)
        #expect(frame.value(at: 1) == 1 && frame.value(at: 2) == 1)
    }

    /// Opening grows into free air and springs; closing lands on the player, so it closes on the
    /// ease out unless that's turned off.
    @Test func closingLandsSoft() {
        var style = PlatterMotionStyle.standard
        style.curve = .easeOutSpring
        #expect(style.animation(opening: false, scaled: atSpeed) == .timingCurve(style.easeOutCurve, duration: 0.4))
        guard case .curve = style.frameCurve(opening: false, scaled: atSpeed) else {
            Issue.record("the window closes on the ease out too"); return
        }
        style.softClose = false
        #expect(style.animation(opening: false, scaled: atSpeed) == Animation(style.easeOutSpring(scaled: atSpeed)))
        // The other curves are the same both ways.
        style.curve = .easeOut
        #expect(style.animation(opening: false, scaled: atSpeed) == style.animation(opening: true, scaled: atSpeed))
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
        #expect(style.swiftSnippet.contains("platterMotion = PlatterMotionStyle(curve: .current, easeOutX1: 0.20, easeOutY1: 0.80, easeOutX2: 0.00, easeOutY2: 1.00, easeOutDuration: 0.40, springDuration: 1.00, springApproach: 0.40, springOvershoot: 0.024, softClose: true)"))
    }
}
