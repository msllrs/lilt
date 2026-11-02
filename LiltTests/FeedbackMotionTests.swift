import SwiftUI
import Testing
@testable import Lilt

/// The quiet confirmation that goes alongside a notice: a band of light across the row a menu
/// action was picked from. Its timing comes from `Theme.Motion`, so the tweak panel's Animation
/// speed slows it like everything else, and under Reduce Motion it doesn't move at all.
@MainActor
struct FeedbackMotionTests {
    private static func at<T>(_ speed: Double, reducing: Bool = false, _ body: () throws -> T) rethrows -> T {
        try MotionPace.$override.withValue(MotionPace(speed: speed, reducesMotion: reducing), operation: body)
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
