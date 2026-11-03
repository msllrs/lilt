import Foundation
import Observation
import SwiftUI

/// How one page hands over to the next as pages are pushed and popped: the transition lab.
/// `current` is the column's long-standing hand-off and stays the default until another is
/// picked in the tweak panel (Page transition); the rest are alternatives to try live.
enum PageTransition: String, CaseIterable, Identifiable, Codable, Sendable {
    /// The page beneath parks 20pt aside and fades over `pageExit` while the new page slides
    /// 20pt in over `pageEnter`, both from the same instant: the two overlap.
    case current
    /// Fade-through with a nudge: the old page is gone (0.09s) before the new one starts, so
    /// nothing is ever superimposed.
    case sequencedFade
    /// The new page slides in from the trailing edge while the old one drifts a third as far
    /// the other way, dimming fully within a tenth of a second (the glass has no backing to
    /// hide it behind).
    case pushParallax
    /// The old page recedes to 97% and fades; the new one settles from 103%, a beat later.
    case scaleDepth
    /// The tapped row's cover flies to the page's hero cover; the rest of the page fades in
    /// around it.
    case heroMorph
    /// The page's parts come in one after another: hero, title, buttons, then rows.
    case staggered
    /// The old page blurs as it fades; the new one sharpens in.
    case blurCut
    /// Current's hand-off, 20pt aside on its ease-out, but sequenced and through the blur: the
    /// old page blurs as it fades and drifts away, the new one sharpens in as it slides into
    /// place.
    case blurSlide
    /// A soft-edged mask sweeps across: every point shows one page or the other, never both.
    case maskedWipe

    var id: String { rawValue }

    var title: String {
        switch self {
        case .current: "Current"
        case .sequencedFade: "Sequenced fade"
        case .pushParallax: "Push with parallax"
        case .scaleDepth: "Scale into depth"
        case .heroMorph: "Hero morph"
        case .staggered: "Staggered entry"
        case .blurCut: "Blur-through cut"
        case .blurSlide: "Blur + slide"
        case .maskedWipe: "Masked wipe"
        }
    }

    /// The dials that mean something for this variant, for the tweak panel to show.
    var dials: Set<PageTransitionDials.Dial> {
        switch self {
        case .current: []
        case .sequencedFade: [.duration, .travel, .stagger]
        case .pushParallax: [.duration, .travel, .stagger, .scale]
        case .scaleDepth: [.duration, .stagger, .scale]
        case .heroMorph: [.duration, .travel, .stagger]
        case .staggered: [.duration, .travel, .stagger]
        case .blurCut: [.duration, .stagger, .scale, .blur]
        case .blurSlide: [.duration, .travel, .stagger, .blur]
        case .maskedWipe: [.duration, .travel, .blur]
        }
    }
}

/// The five dials each variant keeps for itself. What each one moves depends on the variant
/// (see `PageChoreography.make`); the tweak panel says so beside each.
struct PageTransitionDials: Codable, Equatable, Sendable {
    enum Dial: String, CaseIterable, Sendable { case duration, travel, stagger, scale, blur }

    /// Seconds, as designed (at 1×): the incoming page's main motion.
    var duration: Double
    /// Points.
    var travel: Double
    /// Seconds between one thing starting and the next.
    var stagger: Double
    /// A scale step, as a fraction (0.03 is 3%).
    var scale: Double
    /// Points of blur (for the masked wipe, its soft edge).
    var blur: Double

    static let ranges: [Dial: ClosedRange<Double>] = [
        .duration: 0.05...1,
        .travel: 0...200,
        .stagger: 0...0.2,
        .scale: 0...0.2,
        .blur: 0...40,
    ]

    static func defaults(for transition: PageTransition) -> PageTransitionDials {
        switch transition {
        // Not read: Current is built from the Theme.Motion page tokens as it always was.
        case .current: PageTransitionDials(duration: 0.2, travel: 20, stagger: 0, scale: 0, blur: 0)
        case .sequencedFade: PageTransitionDials(duration: 0.24, travel: 12, stagger: 0.07, scale: 0, blur: 0)
        case .pushParallax: PageTransitionDials(duration: 0.38, travel: 120, stagger: 0.04, scale: 0, blur: 0)
        case .scaleDepth: PageTransitionDials(duration: 0.28, travel: 0, stagger: 0.07, scale: 0.03, blur: 0)
        case .heroMorph: PageTransitionDials(duration: 0.36, travel: 6, stagger: 0.02, scale: 0, blur: 0)
        case .staggered: PageTransitionDials(duration: 0.22, travel: 10, stagger: 0.025, scale: 0, blur: 0)
        case .blurCut: PageTransitionDials(duration: 0.2, travel: 0, stagger: 0.08, scale: 0, blur: 8)
        case .blurSlide: PageTransitionDials(duration: 0.2, travel: 20, stagger: 0.08, scale: 0, blur: 8)
        case .maskedWipe: PageTransitionDials(duration: 0.26, travel: 6, stagger: 0, scale: 0, blur: 32)
        }
    }

    subscript(dial: Dial) -> Double {
        get {
            switch dial {
            case .duration: duration
            case .travel: travel
            case .stagger: stagger
            case .scale: scale
            case .blur: blur
            }
        }
        set {
            let value = min(max(newValue, Self.ranges[dial]!.lowerBound), Self.ranges[dial]!.upperBound)
            switch dial {
            case .duration: duration = value
            case .travel: travel = value
            case .stagger: stagger = value
            case .scale: scale = value
            case .blur: blur = value
            }
        }
    }
}

/// The variant in use and every variant's dials, remembered across launches. Release builds
/// always use `current`: the lab is a debug tool until one is chosen.
@MainActor
@Observable
final class PageTransitionSettings {
    static let shared = PageTransitionSettings()

    nonisolated static let transitionKey = "pageTransition"
    nonisolated static let dialsKey = "pageTransitionDials"

    @ObservationIgnored private let defaults: UserDefaults

    #if DEBUG
    var transition: PageTransition { didSet { defaults.set(transition.rawValue, forKey: Self.transitionKey) } }
    #else
    var transition: PageTransition { .current }
    #endif

    /// Every variant's dials that differ from its defaults.
    private var stored: [PageTransition: PageTransitionDials] { didSet { save() } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        #if DEBUG
        transition = defaults.string(forKey: Self.transitionKey).flatMap(PageTransition.init(rawValue:)) ?? .current
        #endif
        if let data = defaults.data(forKey: Self.dialsKey),
           let decoded = try? JSONDecoder().decode([String: PageTransitionDials].self, from: data) {
            stored = Dictionary(uniqueKeysWithValues: decoded.compactMap { key, value in PageTransition(rawValue: key).map { ($0, value) } })
        } else {
            stored = [:]
        }
    }

    func dials(for transition: PageTransition) -> PageTransitionDials {
        stored[transition] ?? PageTransitionDials.defaults(for: transition)
    }

    func setDials(_ dials: PageTransitionDials, for transition: PageTransition) {
        stored[transition] = dials == PageTransitionDials.defaults(for: transition) ? nil : dials
    }

    func resetDials(for transition: PageTransition) { stored[transition] = nil }

    /// The variant on screen, at the current pace.
    var choreography: PageChoreography { PageChoreography.make(transition, dials: dials(for: transition)) }

    private func save() {
        let encoded = Dictionary(uniqueKeysWithValues: stored.map { ($0.key.rawValue, $0.value) })
        if encoded.isEmpty {
            defaults.removeObject(forKey: Self.dialsKey)
        } else if let data = try? JSONEncoder().encode(encoded) {
            defaults.set(data, forKey: Self.dialsKey)
        }
    }
}

// MARK: - Timing

/// A curve a page's motion follows, kept as data so a test can sample it frame by frame.
enum PageCurve: Equatable, Sendable {
    case easeOut
    case easeInOut
    case linear
    /// A cubic Bézier timing curve, as CSS writes one.
    case bezier(Double, Double, Double, Double)
    /// A spring of no bounce over the phase's duration.
    case spring

    fileprivate var unitCurve: UnitCurve? {
        switch self {
        case .easeOut: .easeOut
        case .easeInOut: .easeInOut
        case .linear: .linear
        case .bezier(let x1, let y1, let x2, let y2): .bezier(startControlPoint: UnitPoint(x: x1, y: y1), endControlPoint: UnitPoint(x: x2, y: y2))
        case .spring: nil
        }
    }
}

/// One change over time: wait `delay`, then run `duration` along `curve`.
struct PagePhase: Equatable, Sendable {
    var delay: TimeInterval
    var duration: TimeInterval
    var curve: PageCurve

    static let instant = PagePhase(delay: 0, duration: 0, curve: .linear)

    /// When the change has (visually) finished.
    var end: TimeInterval { delay + duration }

    /// When the change has come to rest: a spring runs on past its duration to its settling.
    var settled: TimeInterval {
        delay + (curve == .spring && duration > 0 ? Spring(duration: duration, bounce: 0).settlingDuration : duration)
    }

    var animation: Animation {
        let base: Animation = switch curve {
        case .easeOut: .easeOut(duration: max(duration, 0.0001))
        case .spring: .spring(duration: max(duration, 0.0001), bounce: 0)
        default: .timingCurve(curve.unitCurve!, duration: max(duration, 0.0001))
        }
        return delay > 0 ? base.delay(delay) : base
    }

    /// How far along the change is at `time` seconds after it was asked for: 0 before the
    /// delay ends, 1 once it's done. A spring is run to its settling, not just its duration.
    func progress(at time: TimeInterval) -> Double {
        let t = time - delay
        guard t > 0 else { return 0 }
        guard duration > 0 else { return 1 }
        switch curve {
        case .spring:
            let spring = Spring(duration: duration, bounce: 0)
            return t >= spring.settlingDuration ? 1 : spring.value(fromValue: 0.0, toValue: 1.0, initialVelocity: 0.0, time: t)
        case .easeOut:
            // SwiftUI's easeOut is the CSS ease-out curve.
            return UnitCurve.easeOut.value(at: min(t / duration, 1))
        default:
            return curve.unitCurve!.value(at: min(t / duration, 1))
        }
    }
}

/// How a page looks away from its place: parked beneath the page on top (`behind`), or not
/// yet arrived / just popped (`front`). At its place every page is plain (`shown`).
struct PageLook: Equatable, Sendable {
    var opacity: Double = 1
    var x: CGFloat = 0
    var y: CGFloat = 0
    var scale: CGFloat = 1
    /// The masked wipe: the part of the page's width that shows, leading to trailing, 0...1.
    var maskLeading: CGFloat = 0
    var maskTrailing: CGFloat = 1

    static let shown = PageLook()

    /// Part way from shown (0) to this look (1), as an animation would draw it.
    func interpolated(_ amount: Double) -> PageLook {
        let shown = PageLook.shown
        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * CGFloat(amount) }
        return PageLook(
            opacity: shown.opacity + (opacity - shown.opacity) * amount,
            x: mix(shown.x, x), y: mix(shown.y, y), scale: mix(shown.scale, scale),
            maskLeading: mix(shown.maskLeading, maskLeading), maskTrailing: mix(shown.maskTrailing, maskTrailing)
        )
    }
}

/// When one page's opacity and its motion (offset, scale, mask) change.
struct PageTiming: Equatable, Sendable {
    var opacity: PagePhase
    var motion: PagePhase
    var end: TimeInterval { max(opacity.end, motion.end) }

    static let instant = PageTiming(opacity: .instant, motion: .instant)
}

/// What a navigation did to the stack.
enum PageMove: Equatable, Sendable {
    /// A page opened on top of the one that was showing.
    case push
    /// One or more pages taken off; `levels` is how many.
    case pop(levels: Int)
    /// Anything else (a stack replaced outright), or nothing at all.
    case none

    static func between(_ old: [String], _ new: [String]) -> PageMove {
        if new.count > old.count, Array(new.prefix(old.count)) == old { return .push }
        if new.count < old.count, Array(old.prefix(new.count)) == new { return .pop(levels: old.count - new.count) }
        return .none
    }
}

/// When the pieces of an arriving page come in, for variants that bring them in one by one.
struct EntrancePlan: Equatable, Sendable {
    enum Slot: Equatable, Sendable {
        case hero, title, controls
        /// A row of the page's list, counted from the top (its section header is row 0).
        case row(Int)
    }

    var hero: TimeInterval
    var title: TimeInterval
    var controls: TimeInterval
    var firstRow: TimeInterval
    var rowStep: TimeInterval
    /// Rows past this one come in with it, so a long page doesn't trickle in.
    var rowCap: Int
    /// Each piece's own fade and rise.
    var duration: TimeInterval
    var curve: PageCurve
    var rise: CGFloat
    /// The hero cover rises with the rest; not when a ghost of it flies there instead.
    var heroRises = true

    func phase(for slot: Slot) -> PagePhase {
        let delay: TimeInterval = switch slot {
        case .hero: hero
        case .title: title
        case .controls: controls
        case .row(let index): firstRow + rowStep * Double(min(max(index, 0), rowCap))
        }
        return PagePhase(delay: delay, duration: duration, curve: curve)
    }

    /// Pieces built after this long (a row scrolled to later) just appear.
    var window: TimeInterval { phase(for: .row(rowCap)).delay + 0.1 }
}

/// A variant resolved at the current pace: how each page looks away from its place, and when
/// it moves in each of the four roles a page can play.
struct PageChoreography: Equatable, Sendable {
    var transition: PageTransition
    var behind: PageLook
    var front: PageLook
    /// The page beneath, getting out of the way of a page pushed over it.
    var park: PageTiming
    /// The page beneath coming back as the one on top is popped.
    var unpark: PageTiming
    /// A page pushed on.
    var insert: PageTiming
    /// A page popped off.
    var remove: PageTiming
    var scaleAnchor: UnitPoint = .top
    /// The incoming page's parts come in one by one (`staggered`, `heroMorph`).
    var entrance: EntrancePlan? = nil
    /// The hero cover's flight from the tapped row (`heroMorph`).
    var flight: PagePhase? = nil
    /// The wipe's soft edge, in points.
    var maskFeather: CGFloat = 0
    var usesMask: Bool { maskFeather > 0 }
    /// The most the move blurs (`BlurVeil`), in points; nothing when 0.
    var veilBlur: CGFloat = 0

    /// The veil's blur `time` seconds into a move: it follows whichever page is showing, none
    /// while the page leaving is fully there, `veilBlur` as the two hand over (both all but
    /// gone), none once the page arriving is fully in.
    func veil(at time: TimeInterval, for move: PageMove) -> Double {
        guard veilBlur > 0, let o = opacities(for: move, at: time) else { return 0 }
        return Double(veilBlur) * (1 - min(max(max(o.outgoing, o.incoming), 0), 1))
    }

    /// The longest any page takes in any role.
    var longest: TimeInterval { [park.end, unpark.end, insert.end, remove.end, flight?.end ?? 0].max() ?? 0 }

    /// When every page in a move has come to rest, springs settled and the flight landed.
    var settled: TimeInterval {
        ([park, unpark, insert, remove].flatMap { [$0.opacity.settled, $0.motion.settled] } + [flight?.settled ?? 0]).max() ?? 0
    }

    /// The page leaving and the page arriving in a move, each as (look away from its place,
    /// whether it is heading there or coming from there, timing).
    struct Pair: Equatable, Sendable {
        var outgoing: (look: PageLook, timing: PageTiming)
        var incoming: (look: PageLook, timing: PageTiming)
        static func == (a: Pair, b: Pair) -> Bool {
            a.outgoing.look == b.outgoing.look && a.outgoing.timing == b.outgoing.timing
                && a.incoming.look == b.incoming.look && a.incoming.timing == b.incoming.timing
        }
    }

    /// Push: the top page parks behind and the new one arrives from the front. Pop: the top
    /// page leaves to the front and the one beneath returns from behind. Popping several levels
    /// at once animates only the page that was showing and the one revealed; the ones between
    /// were already parked out of sight.
    func pair(for move: PageMove) -> Pair? {
        switch move {
        case .push: Pair(outgoing: (behind, park), incoming: (front, insert))
        case .pop: Pair(outgoing: (front, remove), incoming: (behind, unpark))
        case .none: nil
        }
    }

    /// Opacity of the leaving and arriving pages `time` seconds into a move, for checking that
    /// the two never show at once.
    func opacities(for move: PageMove, at time: TimeInterval) -> (outgoing: Double, incoming: Double)? {
        guard let pair = pair(for: move) else { return nil }
        let out = pair.outgoing.look.interpolated(min(max(pair.outgoing.timing.opacity.progress(at: time), 0), 1)).opacity
        let into = pair.incoming.look.interpolated(1 - min(max(pair.incoming.timing.opacity.progress(at: time), 0), 1)).opacity
        return (out, into)
    }

    /// The variant at the current `MotionPace`: every duration and delay stretched by the
    /// Animation speed; under Reduce Motion every variant but `current` is a short crossfade.
    static func make(_ transition: PageTransition, dials: PageTransitionDials, pace: MotionPace = .current) -> PageChoreography {
        func s(_ seconds: TimeInterval) -> TimeInterval { pace.scaled(seconds) }
        func phase(_ delay: TimeInterval, _ duration: TimeInterval, _ curve: PageCurve) -> PagePhase {
            PagePhase(delay: s(delay), duration: s(duration), curve: curve)
        }
        func timing(_ both: PagePhase) -> PageTiming { PageTiming(opacity: both, motion: both) }

        if transition == .current {
            // As NavigationColumn has always done it: parking and unparking both on pageExit,
            // arriving and leaving on pageEnter, all from the same instant.
            let exit = phase(0, 0.12, .easeOut)
            let enter = phase(0, 0.2, .easeOut)
            let travel: CGFloat = pace.reducesMotion ? 0 : 20
            return PageChoreography(
                transition: transition,
                behind: PageLook(opacity: 0, x: -travel), front: PageLook(opacity: 0, x: travel),
                park: timing(exit), unpark: timing(exit), insert: timing(enter), remove: timing(enter)
            )
        }

        if pace.reducesMotion {
            // Nothing travels, scales, blurs or flies: the old page fades out quickly and the new
            // one fades in just behind it.
            let out = timing(phase(0, 0.1, .easeOut))
            let into = timing(phase(0.06, 0.16, .easeOut))
            return PageChoreography(
                transition: transition,
                behind: PageLook(opacity: 0), front: PageLook(opacity: 0),
                park: out, unpark: into, insert: into, remove: out
            )
        }

        let d = dials
        // The quick fade every variant but the wipe leaves by.
        let leave = phase(0, 0.09, .easeOut)
        switch transition {
        case .current:
            fatalError("handled above")

        case .sequencedFade:
            // Out in 0.09s, nudged a little the other way; in from `stagger`, rising into place.
            let arrive = timing(phase(d.stagger, d.duration, .spring))
            return PageChoreography(
                transition: transition,
                behind: PageLook(opacity: 0, x: -d.travel * 2 / 3), front: PageLook(opacity: 0, x: d.travel),
                park: timing(leave), unpark: arrive, insert: arrive, remove: timing(leave)
            )

        case .pushParallax:
            // The page on top travels the full `travel`; the one beneath a third as far. The
            // page going away is fully dimmed within 0.1s, since the glass gives pages no
            // backing to slide over; the arriving one fades in from `stagger`.
            let motion = phase(0, d.duration, .spring)
            let away = PageTiming(opacity: phase(0, 0.1, .easeOut), motion: motion)
            let arrive = PageTiming(opacity: phase(d.stagger, 0.18, .easeOut), motion: motion)
            return PageChoreography(
                transition: transition,
                behind: PageLook(opacity: 0, x: -d.travel * 0.3, scale: 1 - d.scale), front: PageLook(opacity: 0, x: d.travel),
                park: away, unpark: arrive, insert: arrive, remove: away
            )

        case .scaleDepth:
            // Recedes to 1 - scale (from the top, so the header barely moves); the new page
            // settles from 1 + scale a beat later. Pop reverses it.
            let away = timing(phase(0, 0.1, .easeOut))
            let arrive = timing(phase(d.stagger, d.duration, .spring))
            return PageChoreography(
                transition: transition,
                behind: PageLook(opacity: 0, scale: 1 - d.scale), front: PageLook(opacity: 0, scale: 1 + d.scale),
                park: away, unpark: arrive, insert: arrive, remove: away,
                scaleAnchor: .top
            )

        case .heroMorph:
            // The page itself fades through quickly; the cover flies, and the title, buttons and
            // rows follow it in (a page come back to the same way, its cover flying back to its
            // row) (title at 0.08s, buttons 0.04s later, rows from 0.08s after
            // that, `stagger` apart, capped at six).
            let arrive = timing(phase(0.08, 0.15, .easeOut))
            let plan = EntrancePlan(
                hero: 0, title: s(0.08), controls: s(0.12), firstRow: s(0.2), rowStep: s(d.stagger), rowCap: 6,
                duration: s(0.24), curve: .spring, rise: d.travel, heroRises: false
            )
            return PageChoreography(
                transition: transition,
                behind: PageLook(opacity: 0), front: PageLook(opacity: 0),
                park: timing(leave), unpark: arrive, insert: arrive, remove: timing(leave),
                entrance: plan, flight: phase(0, d.duration, .spring)
            )

        case .staggered:
            // A quick fade out; the new page's frame (header, ambient light) fades in behind it
            // and its parts rise in order, `stagger` apart, capped at twelve rows. A page come
            // back to by a pop comes in the same way.
            let start = 0.08
            let arrive = timing(phase(start, 0.12, .easeOut))
            let plan = EntrancePlan(
                hero: s(start), title: s(start + d.stagger), controls: s(start + 2 * d.stagger),
                firstRow: s(start + 3 * d.stagger), rowStep: s(d.stagger), rowCap: 12,
                duration: s(d.duration), curve: .spring, rise: d.travel
            )
            return PageChoreography(
                transition: transition,
                behind: PageLook(opacity: 0), front: PageLook(opacity: 0),
                park: timing(leave), unpark: arrive, insert: arrive, remove: timing(leave),
                entrance: plan
            )

        case .blurCut:
            // Blur follows the fade (see BlurVeil), so it is at its strongest only as a page
            // is nearly gone, and nothing is blurred once a page has settled either way.
            let away = timing(phase(0, 0.1, .easeOut))
            let arrive = timing(phase(d.stagger, d.duration, .easeOut))
            return PageChoreography(
                transition: transition,
                behind: PageLook(opacity: 0, scale: 1 - d.scale), front: PageLook(opacity: 0, scale: 1 + d.scale),
                park: away, unpark: arrive, insert: arrive, remove: away,
                veilBlur: d.blur
            )

        case .blurSlide:
            // Current's travel and curve: the page going away drifts `travel` aside over 0.2s on
            // an ease-out as Current's does, but is faded within 0.1s; the page arriving fades
            // and slides in together from `stagger`, over `duration`. The veil blurs the hand-over,
            // so each page is sharp only where it is fully there.
            let away = PageTiming(opacity: phase(0, 0.1, .easeOut), motion: phase(0, 0.2, .easeOut))
            let arrive = timing(phase(d.stagger, d.duration, .easeOut))
            return PageChoreography(
                transition: transition,
                behind: PageLook(opacity: 0, x: -d.travel), front: PageLook(opacity: 0, x: d.travel),
                park: away, unpark: arrive, insert: arrive, remove: away,
                veilBlur: d.blur
            )

        case .maskedWipe:
            // One edge sweeps across: the arriving page shows on one side of it and the leaving
            // page on the other, a `blur`-wide soft edge between. Push sweeps trailing to
            // leading, pop back again. A page out of the way is also faded to nothing once the
            // sweep is over, so a parked page draws nothing at all.
            let sweep = phase(0, d.duration, .bezier(0.3, 0, 0, 1))
            let away = PageTiming(opacity: phase(d.duration, 0, .linear), motion: sweep)
            let arrive = PageTiming(opacity: .instant, motion: sweep)
            return PageChoreography(
                transition: transition,
                behind: PageLook(opacity: 0, maskLeading: 0, maskTrailing: 0),
                front: PageLook(opacity: 0, x: d.travel, maskLeading: 1, maskTrailing: 1),
                park: away, unpark: arrive, insert: arrive, remove: away,
                maskFeather: max(d.blur, 1)
            )
        }
    }
}

/// The wipe's mask as gradient stops across the page: opaque between `leading` and
/// `trailing` (fractions of the width), with a soft edge `feather` wide on each side; outside
/// the page's width at 0 and 1, so a fully shown page has no soft edge and a hidden one shows
/// nothing at all.
nonisolated enum WipeMask {
    static func alpha(at u: CGFloat, leading: CGFloat, trailing: CGFloat, feather f: CGFloat) -> CGFloat {
        let lo = leading * (1 + f) - f
        let hi = trailing * (1 + f)
        let rise = (u - lo) / f
        let fall = (hi - u) / f
        return min(max(min(rise, fall), 0), 1)
    }

    static func stops(leading: CGFloat, trailing: CGFloat, feather: CGFloat) -> [Gradient.Stop] {
        let f = max(feather, 0.0001)
        let lo = leading * (1 + f) - f
        let hi = trailing * (1 + f)
        let breaks = [0, 1, lo, lo + f, hi - f, hi].filter { $0 >= 0 && $0 <= 1 }
        return Set(breaks).sorted().map { Gradient.Stop(color: .black.opacity(alpha(at: $0, leading: leading, trailing: trailing, feather: f)), location: $0) }
    }
}
