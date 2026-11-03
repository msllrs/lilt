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
            // Frames measured inside the page (the hero morph's) ignore how it is staged.
            .coordinateSpace(.named(PageSpace.name))
            .modifier(PageStage(look: look, timing: timing, blur: blur, anchor: c.scaleAnchor, maskFeather: feather, flattens: true))
            .allowsHitTesting(!parked)
            .accessibilityHidden(parked)
            // Discs, notes and marquees stop while a screen sits unseen beneath another or leaves.
            .environment(\.screenIsParked, parked || outOfSight)
            .onAppear { arrived = true }
    }
}

/// The column's stack of screens for every variant but Current: the root, then each page of
/// `path`, each staged by the choreography (see StagedScreen) with a timing of its own for each
/// role (parking, coming back, arriving, leaving), so the page going away and the page arriving
/// can be sequenced rather than overlap. No animation on the stack as a whole: it would hand
/// every page the same one.
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
    /// Pages popped and still on their way out, and the path as last drawn.
    @State private var leaving: [BrowseItem] = []
    @State private var shownPath: [BrowseItem] = []
    /// Pages there when the column first appears (a relaunch) don't slide in.
    @State private var hasAppeared = false

    var body: some View {
        let ids = Set(path.map(\.id))
        // Popped pages stay until they've left: those already on their way, and, in the very
        // update that pops them (before onChange has run), the ones just taken off, so their
        // views carry on rather than being rebuilt. A page pushed again while leaving is simply
        // the page on top again, from wherever it had got to.
        var gone = leaving.filter { !ids.contains($0.id) }
        for item in shownPath where !ids.contains(item.id) && !gone.contains(where: { $0.id == item.id }) { gone.append(item) }
        return ZStack {
            StagedScreen(position: path.isEmpty ? .top : .behind, choreography: choreography, width: width, outOfSight: outOfSight, arrives: false) {
                root
                    .environment(\.pageEntrance, entrance(PageSpace.searchKey))
                    .environment(\.pageKey, PageSpace.searchKey)
            }
            // One ForEach for pages on the path and pages leaving, so a page popped (or pushed
            // back while leaving) keeps its view as it changes role.
            let entries = path.enumerated().map { ($1, $0 == path.count - 1 ? StagedPosition.top : .behind) } + gone.map { ($0, StagedPosition.leaving) }
            ForEach(entries, id: \.0.id) { item, position in
                StagedScreen(position: position, choreography: choreography, width: width, outOfSight: outOfSight, arrives: hasAppeared) {
                    page(item)
                        .environment(\.pageEntrance, entrance(item.id))
                        .environment(\.pageKey, item.id)
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .onAppear { hasAppeared = true; shownPath = path }
        .onChange(of: path) { old, new in
            let now = Set(new.map(\.id))
            let popped = old.filter { !now.contains($0.id) }
            leaving.removeAll { now.contains($0.id) }
            leaving.append(contentsOf: popped.filter { item in !leaving.contains(where: { $0.id == item.id }) })
            shownPath = new
            guard !popped.isEmpty else { return }
            // Let them go once they've left; a later pop's own wait sees to its pages.
            let ids = Set(popped.map(\.id))
            let wait = choreography.remove.end + 0.05
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(wait))
                leaving.removeAll { ids.contains($0.id) && !shownPath.contains($0) }
            }
        }
    }
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
