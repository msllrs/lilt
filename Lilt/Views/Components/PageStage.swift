import SwiftUI

/// Draws a screen of the navigation stack at a `PageLook`: in its place, or part of the way
/// to (or from) where it waits behind the page on top or in front before it arrives. Offset
/// and scale ride the timing's motion phase, the fade its opacity phase, each through its own
/// scoped animation, so a page can be gone long before it has finished moving. Only opacity,
/// travel and scale animate on the flattened page; blur and the wipe's mask are there only for
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
                $0.modifier(PageSlide(x: look.x, y: look.y))
                    .scaleEffect(look.scale, anchor: anchor)
            }
        let flat = Group {
            if flattens { moved.compositingGroup() } else { moved }
        }
        // A plain fade for every variant but the blur-through cut: FadeBlur is a custom
        // animatable, evaluated on every frame of the fade.
        let faded = Group {
            if blur > 0 {
                flat.animation(timing.opacity.animation) { $0.modifier(FadeBlur(opacity: look.opacity, blur: blur)) }
            } else {
                flat.animation(timing.opacity.animation) { $0.opacity(look.opacity) }
            }
        }
        if let maskFeather {
            faded.animation(timing.motion.animation) {
                $0.modifier(WipeMaskEffect(leading: look.maskLeading, trailing: look.maskTrailing, feather: maskFeather))
            }
        } else {
            faded
        }
    }
}

/// A page's travel as a render transform. Not `offset`: an offset moves a page's AppKit views
/// (its scroll view) by their frames, and a frame change takes the update's own transaction,
/// not a scoped animation, so under `PageStage` it landed in one step on the first frame (12pt
/// for the sequenced fade, 120pt for the parallax) while the fade around it animated. A
/// transform, like the scale beside it, is drawn, so it animates where it's scoped.
nonisolated struct PageSlide: GeometryEffect {
    var x: CGFloat
    var y: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(x, y) }
        set { x = newValue.first; y = newValue.second }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: x, y: y))
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

/// The column's stack of screens for every variant but Current, on the same mechanics as
/// Current: the root and each page of `path` stay mounted, each parked behind the page on top
/// or in its place, and a page arrives and leaves by a SwiftUI transition. What differs is that
/// every role has a timing of its own (parking, coming back, arriving, leaving) with its fade
/// and its motion as separate scoped animations, so the page going away and the page arriving
/// can be sequenced rather than overlap. No animation on the stack as a whole: it would hand
/// every page the same one.
///
/// A popped page is left as it was while it leaves (nothing in it is evaluated again) and is
/// let go only once the whole move has settled, so its teardown never lands on a frame of the
/// page coming back.
struct StagedStack<Root: View, Page: View>: View {
    let path: [BrowseItem]
    let choreography: PageChoreography
    let outOfSight: Bool
    /// Each screen's entrance, by its key (`PageSpace.searchKey` for the root).
    let entrance: (String) -> PageEntrance?
    let root: Root
    let page: (BrowseItem) -> Page

    init(path: [BrowseItem], choreography: PageChoreography, outOfSight: Bool, entrance: @escaping (String) -> PageEntrance? = { _ in nil }, @ViewBuilder root: () -> Root, @ViewBuilder page: @escaping (BrowseItem) -> Page) {
        self.path = path
        self.choreography = choreography
        self.outOfSight = outOfSight
        self.entrance = entrance
        self.root = root()
        self.page = page
    }

    /// The column's width, for the masked wipe's soft edge.
    @State private var width: CGFloat = 320

    var body: some View {
        let c = choreography
        let feather: CGFloat? = c.usesMask ? c.maskFeather / max(width, 1) : nil
        ZStack {
            root
                .environment(\.pageEntrance, entrance(PageSpace.searchKey))
                .environment(\.pageKey, PageSpace.searchKey)
                .modifier(StagedPlace(parked: !path.isEmpty, choreography: c, feather: feather, outOfSight: outOfSight))
            ForEach(Array(path.enumerated()), id: \.element.id) { index, item in
                page(item)
                    .environment(\.pageEntrance, entrance(item.id))
                    .environment(\.pageKey, item.id)
                    .modifier(StagedPlace(parked: index < path.count - 1, choreography: c, feather: feather, outOfSight: outOfSight))
                    .transition(PageArrival(choreography: c, feather: feather))
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}

/// A screen in its place on the staged stack, or parked behind the page on top: parking on the
/// `park` timing, coming back on `unpark`. Flattened, so it fades and moves as one layer.
private struct StagedPlace: ViewModifier {
    let parked: Bool
    let choreography: PageChoreography
    let feather: CGFloat?
    let outOfSight: Bool

    func body(content: Content) -> some View {
        let c = choreography
        content
            // Frames measured inside the page (the hero morph's) ignore how it is staged.
            .coordinateSpace(.named(PageSpace.name))
            .modifier(PageStage(look: parked ? c.behind : .shown, timing: parked ? c.park : c.unpark, blur: c.behind.blur, anchor: c.scaleAnchor, maskFeather: feather, flattens: true))
            .allowsHitTesting(!parked)
            .accessibilityHidden(parked)
            // Discs, notes and marquees stop while a screen sits unseen beneath another.
            .environment(\.screenIsParked, parked || outOfSight)
    }
}

/// A page pushed on comes from the `front` look on the `insert` timing; a page popped goes back
/// there on `remove`, and is then held, invisible, until the whole move has settled.
private struct PageArrival: Transition {
    let choreography: PageChoreography
    let feather: CGFloat?

    func body(content: Content, phase: TransitionPhase) -> some View {
        let c = choreography
        content
            .modifier(PageStage(look: phase.isIdentity ? .shown : c.front, timing: phase == .didDisappear ? c.remove : c.insert, blur: c.front.blur, anchor: c.scaleAnchor, maskFeather: feather, flattens: false))
            // SwiftUI keeps a removed view until its transition's animations are done; this one
            // draws nothing and lasts as long as the move.
            .animation(.linear(duration: max(c.settled, 0.0001))) { $0.modifier(RemovalHold(progress: phase == .didDisappear ? 1 : 0)) }
    }
}

/// Animates nothing visible: it only keeps a popped page's removal going (see `PageArrival`).
nonisolated private struct RemovalHold: ViewModifier, Animatable {
    var progress: Double
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }
    func body(content: Content) -> some View { content }
}

/// The screen that last came in on top (pushed, or revealed by a pop), for variants that bring
/// its parts in one by one: when it came in and when each part does.
struct PageEntrance: Equatable {
    let plan: EntrancePlan
    let startedAt: Date

    /// Parts built after this (a row scrolled to later, content that loaded late) just appear.
    var isFresh: Bool { Date().timeIntervalSince(startedAt) < plan.window }
}

extension EnvironmentValues {
    /// Set on a screen while the variant staggers its parts in, stamped each time the screen
    /// comes in on top; nil everywhere else.
    @Entry var pageEntrance: PageEntrance? = nil
}

/// One part of a page coming in on its slot's delay: drawn faded and lowered by the plan's rise
/// on its first frame (or, on a page come back to, the frame its entrance is stamped), then
/// rising into place. Outside a fresh entrance it is simply there.
private struct EntranceItem: ViewModifier {
    let slot: EntrancePlan.Slot
    @Environment(\.pageEntrance) private var entrance
    /// The entrance this part has come in for.
    @State private var seen: Date?

    func body(content: Content) -> some View {
        let pending = entrance.map { $0.startedAt != seen && $0.isFresh } ?? false
        content
            // Hidden at once (it may be on screen, about to come in again), brought in on its
            // slot's delay.
            .animation(pending ? nil : entrance?.plan.phase(for: slot).animation) {
                $0.opacity(pending ? 0 : 1)
                    .offset(y: pending && (slot != .hero || entrance?.plan.heroRises == true) ? entrance?.plan.rise ?? 0 : 0)
            }
            .onAppear { if let entrance, entrance.isFresh { seen = entrance.startedAt } }
            .onChange(of: entrance?.startedAt) { _, started in if entrance?.isFresh == true { seen = started } }
    }
}

extension View {
    /// Brings this part of a page in at its place in the entrance (`staggered`, `heroMorph`).
    func entrance(_ slot: EntrancePlan.Slot) -> some View { modifier(EntranceItem(slot: slot)) }
}
