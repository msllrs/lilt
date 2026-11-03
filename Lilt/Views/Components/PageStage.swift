import SwiftUI

/// Draws a screen of the navigation stack at a `PageLook`: in its place, or part of the way
/// to (or from) where it waits behind the page on top or in front before it arrives. Offset
/// and scale ride the timing's motion phase, the fade its opacity phase, each through its own
/// scoped animation, so a page can be gone long before it has finished moving. Only opacity,
/// offset and scale animate on the flattened page; blur and the wipe's mask are there only for
/// the variants that use them.
struct PageStage: ViewModifier {
    let look: PageLook
    let timing: PageTiming
    /// The blur this stage reaches as its page fades out entirely (see `FadeBlur`).
    let blur: CGFloat
    let anchor: UnitPoint
    /// The wipe's soft edge as a fraction of the page's width; nil when the variant has no mask.
    let maskFeather: CGFloat?
    /// Fade the page as one flattened layer rather than row by row (as `parked` always has).
    let flattens: Bool

    func body(content: Content) -> some View {
        let moved = content
            .animation(timing.motion.animation) {
                $0.offset(x: look.x, y: look.y)
                    .scaleEffect(look.scale, anchor: anchor)
            }
        let faded = Group {
            if flattens { moved.compositingGroup() } else { moved }
        }
        .animation(timing.opacity.animation) { $0.modifier(FadeBlur(opacity: look.opacity, blur: blur)) }
        if let maskFeather {
            faded.animation(timing.motion.animation) {
                $0.modifier(WipeMaskEffect(leading: look.maskLeading, trailing: look.maskTrailing, feather: maskFeather))
            }
        } else {
            faded
        }
    }
}

/// A page's fade, with its blur following it: none while the page is fully there, the most as
/// it all but disappears, and none again once it has (a page faded out isn't left blurred
/// beneath the one on top, costing a filter for nothing).
nonisolated private struct FadeBlur: ViewModifier, Animatable {
    var opacity: Double
    let blur: CGFloat

    var animatableData: Double {
        get { opacity }
        set { opacity = newValue }
    }

    func body(content: Content) -> some View {
        content
            .blur(radius: blur > 0 && opacity > 0.01 && opacity < 1 ? blur * CGFloat(1 - opacity) : 0)
            .opacity(opacity)
    }
}

/// The masked wipe: the page shows between two edges that sweep across it (see `WipeMask`).
nonisolated private struct WipeMaskEffect: ViewModifier, Animatable {
    var leading: CGFloat
    var trailing: CGFloat
    let feather: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(leading, trailing) }
        set { leading = newValue.first; trailing = newValue.second }
    }

    func body(content: Content) -> some View {
        content.mask {
            LinearGradient(stops: WipeMask.stops(leading: leading, trailing: trailing, feather: feather), startPoint: .leading, endPoint: .trailing)
        }
    }
}

/// Where a screen of the staged stack is.
enum StagedPosition: Equatable {
    /// The page on top.
    case top
    /// Parked under the page on top.
    case behind
    /// Popped, and on its way out.
    case leaving
}

/// A screen of the staged stack, drawn by `PageStage` at the look its position calls for. A
/// page pushed on is first drawn at the `front` look and arrives from there as it appears, on
/// the `insert` timing; a popped page is kept here (by NavigationColumn) at `.leaving` until
/// its `remove` timing has run. SwiftUI's own insertion and removal transitions aren't used:
/// the page's phases are scoped animations with delays of their own, which a transition
/// neither waits for nor carries.
struct StagedScreen<Content: View>: View {
    let position: StagedPosition
    let choreography: PageChoreography
    let width: CGFloat
    let outOfSight: Bool
    let content: Content

    /// False until a pushed page has appeared, so its first frame is drawn at the front look.
    @State private var arrived: Bool

    /// `arrives`: false for the screens already there when the column first appears (relaunch
    /// restores the stack in place, nothing slides in). Read once, as the screen is built.
    init(position: StagedPosition, choreography: PageChoreography, width: CGFloat, outOfSight: Bool, arrives: Bool, @ViewBuilder content: () -> Content) {
        self.position = position
        self.choreography = choreography
        self.width = width
        self.outOfSight = outOfSight
        self.content = content()
        _arrived = State(initialValue: !arrives)
    }
    /// Where the page last waited away from its place: whether coming back to it is an arrival
    /// (from the front) or a return (from behind) decides its timing, and the blur it sharpens
    /// from. Read and written as the body is built, so it never invalidates a view.
    @State private var memory = Memory()
    private enum Away { case front, behind }
    private final class Memory { var lastAway: Away? = nil }

    var body: some View {
        let c = choreography
        let away: Away? = position == .leaving || !arrived ? .front : position == .behind ? .behind : nil
        let look: PageLook = switch away {
        case .front: c.front
        case .behind: c.behind
        case nil: .shown
        }
        let timing: PageTiming = switch away {
        case .front: c.remove
        case .behind: c.park
        case nil: memory.lastAway == .behind ? c.unpark : c.insert
        }
        // The blur the fade follows: towards the look it's heading for, or from the one it left.
        let blur = (away ?? memory.lastAway).map { $0 == .front ? c.front.blur : c.behind.blur } ?? 0
        if let away { memory.lastAway = away }
        let parked = position != .top
        let feather: CGFloat? = c.usesMask ? c.maskFeather / max(width, 1) : nil
        return content
            .modifier(PageStage(look: look, timing: timing, blur: blur, anchor: c.scaleAnchor, maskFeather: feather, flattens: true))
            .allowsHitTesting(!parked)
            .accessibilityHidden(parked)
            // Discs, notes and marquees stop while a screen sits unseen beneath another or leaves.
            .environment(\.screenIsParked, parked || outOfSight)
            .onAppear { arrived = true }
    }
}

/// The page just pushed, for variants that bring its parts in one by one: when it was pushed
/// and when each part comes in.
struct PageEntrance: Equatable {
    let plan: EntrancePlan
    let startedAt: Date

    /// Parts built after this (a row scrolled to later, content that loaded late) just appear.
    var isFresh: Bool { Date().timeIntervalSince(startedAt) < plan.window }
}

extension EnvironmentValues {
    /// Set on the page just pushed while the variant staggers its parts in; nil everywhere else.
    @Entry var pageEntrance: PageEntrance? = nil
}

/// One part of a page coming in on its slot's delay: drawn faded and lowered by the plan's rise
/// on its first frame, then rising into place. Outside a fresh entrance it is simply there.
private struct EntranceItem: ViewModifier {
    let slot: EntrancePlan.Slot
    @Environment(\.pageEntrance) private var entrance
    @State private var arrived = false

    func body(content: Content) -> some View {
        let pending = !arrived && entrance?.isFresh == true
        content
            .animation(entrance?.plan.phase(for: slot).animation) {
                $0.opacity(pending ? 0 : 1)
                    .offset(y: pending ? entrance?.plan.rise ?? 0 : 0)
            }
            .onAppear { if entrance?.isFresh == true { arrived = true } }
    }
}

extension View {
    /// Brings this part of a page in at its place in the entrance (`staggered`, `heroMorph`).
    func entrance(_ slot: EntrancePlan.Slot) -> some View { modifier(EntranceItem(slot: slot)) }
}
