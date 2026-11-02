import SwiftUI
import Testing
@testable import Lilt

/// The quiet confirmations that go alongside a notice: a control's attention hop, and a band of
/// light across the row a menu action was picked from. Their timing
/// comes from `Theme.Motion`, so the tweak panel's Animation speed slows them like everything
/// else, and under Reduce Motion they don't move at all.
@MainActor
struct FeedbackMotionTests {
    private static func at<T>(_ speed: Double, reducing: Bool = false, _ body: () throws -> T) rethrows -> T {
        try MotionPace.$override.withValue(MotionPace(speed: speed, reducesMotion: reducing), operation: body)
    }

    // MARK: Attention

    @Test func theHopIsTheDialsAtDesignedSpeed() {
        let style = AttentionStyle.standard
        let hop = Self.at(1) { Theme.Motion.attention(style) }
        #expect(hop == .hop(rise: style.rise, settle: Spring(response: style.response, dampingRatio: style.damping), jump: style.jump, scale: style.scale))
    }

    @Test func theHopSlowsWithThePace() {
        let style = AttentionStyle.standard
        for speed in [0.1, 0.25, 0.5] {
            let hop = Self.at(speed) { Theme.Motion.attention(style) }
            // Slower, not bigger: the time stretches, the jump and scale stay.
            #expect(hop == .hop(rise: style.rise / speed, settle: Spring(response: style.response / speed, dampingRatio: style.damping), jump: style.jump, scale: style.scale))
        }
    }

    @Test func theDefaultHopIsSubtle() {
        let style = AttentionStyle.standard
        #expect(style.jump > 0 && style.jump <= Theme.Space.xs)
        #expect(style.scale > 1 && style.scale <= 1.15)
        #expect(style.rise + style.response < 0.6)
    }

    @Test func underReduceMotionTheHopIsOnlyAnOpacityDip() {
        let style = AttentionStyle.standard
        let reduced = Self.at(1, reducing: true) { Theme.Motion.attention(style) }
        #expect(reduced == .pulse(duration: style.pulse, opacity: style.pulseOpacity))
        // A fade, so it still slows with the pace.
        let slowed = Self.at(0.5, reducing: true) { Theme.Motion.attention(style) }
        #expect(slowed == .pulse(duration: style.pulse / 0.5, opacity: style.pulseOpacity))
    }

    // MARK: Shine

    @Test func theShineCrossesInItsDurationAndSlowsWithThePace() {
        let style = ShineStyle.standard
        #expect(Self.at(1) { Theme.Motion.shine(style) } == .easeInOut(duration: style.duration))
        #expect(Self.at(0.25) { Theme.Motion.shine(style) } == .easeInOut(duration: style.duration / 0.25))
        #expect(style.duration == 0.5)
    }

    @Test func underReduceMotionThereIsNoShine() {
        #expect(Self.at(1, reducing: true) { Theme.Motion.shine(.standard) } == nil)
        #expect(Self.at(0.1, reducing: true) { Theme.Motion.shine(.standard) } == nil)
    }

    // MARK: The trigger

    @Test func copyLinkAndTheQueueActionsShineOnceEach() {
        var trigger = ShineTrigger()
        trigger.note(.copyLink)
        #expect(trigger.count == 1)
        trigger.note(.playNext)
        #expect(trigger.count == 2)
        trigger.note(.addToQueue)
        #expect(trigger.count == 3)
    }

    @Test func actionsThatShowThemselvesDontShine() {
        var trigger = ShineTrigger()
        for action: RowAction in [.play, .shuffle, .like, .unlike, .goToArtist, .goToAlbum, .removeFromQueue, .removeFromPlaylist, .addToPlaylist] {
            trigger.note(action)
        }
        #expect(trigger.count == 0)
    }
}
