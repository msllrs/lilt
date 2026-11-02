import SwiftUI

extension View {
    /// A small hop each time `trigger` changes, to confirm a control did what it was asked
    /// without a word: up a little and a touch bigger, then a spring back (see `AttentionStyle`
    /// for the dials). Under Reduce Motion it dips in opacity instead.
    ///
    /// Offset and scale only, so nothing around it moves. Put it on a control's glyph, inside
    /// the frame that gives the control its hit area, so clicks land where they did.
    func attentionBounce(trigger: Int) -> some View {
        modifier(AttentionBounce(trigger: trigger))
    }
}

private struct AttentionBounce: ViewModifier {
    let trigger: Int

    private struct Pose {
        var jump: Double = 0
        var scale: Double = 1
        var opacity: Double = 1
    }

    /// The keyframes' targets: every track is always built, and the one the motion doesn't use
    /// holds at rest.
    private struct Plan {
        var rise: TimeInterval
        var settle = Spring()
        var jump: Double = 0
        var scale: Double = 1
        var pulse: TimeInterval
        var opacity: Double = 1

        init(_ motion: Theme.Motion.Attention) {
            switch motion {
            case .hop(let rise, let settle, let jump, let scale):
                self.rise = rise
                self.settle = settle
                self.jump = jump
                self.scale = scale
                pulse = rise
            case .pulse(let duration, let opacity):
                rise = duration
                pulse = duration
                self.opacity = opacity
            }
        }
    }

    func body(content: Content) -> some View {
        // Resolved here, on the main actor, at the pace of the moment.
        let plan = Plan(Theme.Motion.attention(ArtworkStyle.shared.attention))
        content.keyframeAnimator(initialValue: Pose(), trigger: trigger) { content, pose in
            content
                .scaleEffect(pose.scale)
                .offset(y: -pose.jump)
                .opacity(pose.opacity)
        } keyframes: { _ in
            KeyframeTrack(\.jump) {
                CubicKeyframe(plan.jump, duration: plan.rise)
                SpringKeyframe(0, spring: plan.settle)
            }
            KeyframeTrack(\.scale) {
                CubicKeyframe(plan.scale, duration: plan.rise)
                SpringKeyframe(1, spring: plan.settle)
            }
            KeyframeTrack(\.opacity) {
                CubicKeyframe(plan.opacity, duration: plan.pulse)
                CubicKeyframe(1, duration: plan.pulse)
            }
        }
    }
}
