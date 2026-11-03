import Foundation
import SwiftUI
import Testing
@testable import Lilt

/// The page transition lab: which hand-off is in use is remembered, every variant's timing goes
/// through the motion pace, Reduce Motion turns each into a short crossfade, push and pop each
/// move the right page the right way, and the sequenced variants never show two pages at once.
@MainActor
struct PageTransitionTests {
    private static func at<T>(_ speed: Double, reducing: Bool = false, _ body: () throws -> T) rethrows -> T {
        try MotionPace.$override.withValue(MotionPace(speed: speed, reducesMotion: reducing), operation: body)
    }

    private static func choreography(_ transition: PageTransition, speed: Double = 1, reducing: Bool = false) -> PageChoreography {
        PageChoreography.make(transition, dials: .defaults(for: transition), pace: MotionPace(speed: speed, reducesMotion: reducing))
    }

    // MARK: Persistence

    /// Tests run inside Lilt.app and share its defaults, so the real values are put back.
    private struct SavedDefaults {
        let transition = UserDefaults.standard.object(forKey: PageTransitionSettings.transitionKey)
        let dials = UserDefaults.standard.object(forKey: PageTransitionSettings.dialsKey)
        func restore() {
            let defaults = UserDefaults.standard
            if let transition { defaults.set(transition, forKey: PageTransitionSettings.transitionKey) } else { defaults.removeObject(forKey: PageTransitionSettings.transitionKey) }
            if let dials { defaults.set(dials, forKey: PageTransitionSettings.dialsKey) } else { defaults.removeObject(forKey: PageTransitionSettings.dialsKey) }
        }
    }

    @Test func untilOneIsPickedPagesUseTheCurrentHandOff() {
        let saved = SavedDefaults()
        defer { saved.restore() }
        UserDefaults.standard.removeObject(forKey: PageTransitionSettings.transitionKey)
        UserDefaults.standard.removeObject(forKey: PageTransitionSettings.dialsKey)
        let settings = PageTransitionSettings()
        #expect(settings.transition == .current)
        #expect(settings.dials(for: .sequencedFade) == .defaults(for: .sequencedFade))
    }

    @Test func thePickedVariantAndItsDialsAreRemembered() {
        let saved = SavedDefaults()
        defer { saved.restore() }
        let settings = PageTransitionSettings()
        settings.transition = .pushParallax
        var dials = settings.dials(for: .pushParallax)
        dials.travel = 90
        settings.setDials(dials, for: .pushParallax)

        let relaunched = PageTransitionSettings()
        #expect(relaunched.transition == .pushParallax)
        #expect(relaunched.dials(for: .pushParallax).travel == 90)
        // Another variant's dials are its own.
        #expect(relaunched.dials(for: .scaleDepth) == .defaults(for: .scaleDepth))

        relaunched.resetDials(for: .pushParallax)
        #expect(PageTransitionSettings().dials(for: .pushParallax) == .defaults(for: .pushParallax))
    }

    @Test func anUnknownStoredVariantFallsBackToCurrent() {
        let saved = SavedDefaults()
        defer { saved.restore() }
        UserDefaults.standard.set("somethingRemoved", forKey: PageTransitionSettings.transitionKey)
        #expect(PageTransitionSettings().transition == .current)
    }

    @Test func dialsStayInTheirRanges() {
        var dials = PageTransitionDials.defaults(for: .blurCut)
        dials[.blur] = 500
        dials[.duration] = -1
        #expect(dials.blur == PageTransitionDials.ranges[.blur]!.upperBound)
        #expect(dials.duration == PageTransitionDials.ranges[.duration]!.lowerBound)
    }

    // MARK: Timing

    @Test func currentIsBuiltFromTheShippingPageTokens() {
        for speed in [1, 0.1] {
            Self.at(speed) {
                let c = Self.choreography(.current, speed: speed)
                #expect(c.park.opacity.animation == Theme.Motion.pageExit)
                #expect(c.unpark.opacity.animation == Theme.Motion.pageExit)
                #expect(c.insert.opacity.animation == Theme.Motion.pageEnter)
                #expect(c.remove.opacity.animation == Theme.Motion.pageEnter)
                #expect(c.front.x == Theme.Motion.pageTravel)
                #expect(c.behind.x == -Theme.Motion.pageTravel)
            }
        }
    }

    @Test func designedTimingsAtFullSpeed() {
        let sequenced = Self.choreography(.sequencedFade)
        #expect(sequenced.park.opacity == PagePhase(delay: 0, duration: 0.09, curve: .easeOut))
        #expect(sequenced.insert.opacity == PagePhase(delay: 0.07, duration: 0.24, curve: .spring))
        #expect(sequenced.front.x == 12 && sequenced.behind.x == -8)

        let parallax = Self.choreography(.pushParallax)
        #expect(parallax.insert.motion == PagePhase(delay: 0, duration: 0.38, curve: .spring))
        #expect(parallax.park.opacity.end == 0.1)
        #expect(parallax.front.x == 120 && parallax.behind.x == -36)

        let depth = Self.choreography(.scaleDepth)
        #expect(depth.behind.scale == 0.97 && depth.front.scale == 1.03)
        #expect(depth.park.opacity == PagePhase(delay: 0, duration: 0.1, curve: .easeOut))
        #expect(depth.insert.motion == PagePhase(delay: 0.07, duration: 0.28, curve: .spring))
        #expect(depth.scaleAnchor == .top)

        let hero = Self.choreography(.heroMorph)
        #expect(hero.flight == PagePhase(delay: 0, duration: 0.36, curve: .spring))
        #expect(hero.entrance?.phase(for: .title).delay == 0.08)
        #expect(hero.entrance?.phase(for: .controls).delay == 0.12)
        #expect(abs((hero.entrance?.phase(for: .row(2)).delay ?? 0) - 0.24) < 1e-9)
        // Capped at six rows.
        #expect(hero.entrance?.phase(for: .row(40)) == hero.entrance?.phase(for: .row(6)))

        let staggered = Self.choreography(.staggered)
        let rows = (0..<20).map { staggered.entrance!.phase(for: .row($0)).delay }
        #expect(zip(rows, rows.dropFirst()).allSatisfy { $1 >= $0 })
        #expect(abs(rows[1] - rows[0] - 0.025) < 1e-9)
        #expect(rows[19] == rows[12])
        #expect(staggered.entrance!.phase(for: .hero).delay < staggered.entrance!.phase(for: .title).delay)
        #expect(staggered.entrance!.phase(for: .title).delay < staggered.entrance!.phase(for: .controls).delay)
        #expect(staggered.entrance!.phase(for: .controls).delay < rows[0])

        let blur = Self.choreography(.blurCut)
        #expect(blur.behind.blur == 8 && blur.front.blur == 8)

        let wipe = Self.choreography(.maskedWipe)
        #expect(wipe.insert.motion == PagePhase(delay: 0, duration: 0.26, curve: .bezier(0.3, 0, 0, 1)))
        #expect(wipe.maskFeather == 32)
    }

    /// At a tenth of the speed every delay and duration of every variant is ten times as long,
    /// so slowing the Animation speed shows the same hand-off in slow motion.
    @Test func everyVariantSlowsWithTheAnimationSpeed() {
        func phases(_ c: PageChoreography) -> [PagePhase] {
            var all = [c.park, c.unpark, c.insert, c.remove].flatMap { [$0.opacity, $0.motion] }
            if let flight = c.flight { all.append(flight) }
            if let plan = c.entrance { all += [.hero, .title, .controls, .row(0), .row(3), .row(50)].map(plan.phase(for:)) }
            return all
        }
        for transition in PageTransition.allCases {
            let full = phases(Self.choreography(transition, speed: 1))
            let slow = phases(Self.choreography(transition, speed: 0.1))
            #expect(full.count == slow.count)
            for (a, b) in zip(full, slow) {
                #expect(abs(b.delay - a.delay * 10) < 1e-9, "\(transition) delay")
                #expect(abs(b.duration - a.duration * 10) < 1e-9, "\(transition) duration")
                #expect(a.curve == b.curve)
            }
            #expect(abs(Self.choreography(transition, speed: 0.1).longest - Self.choreography(transition).longest * 10) < 1e-9)
        }
    }

    @Test func theLiveSettingsResolveAtThePaceInForce() {
        let saved = SavedDefaults()
        defer { saved.restore() }
        let settings = PageTransitionSettings()
        settings.transition = .sequencedFade
        let slow = Self.at(0.1) { settings.choreography }
        #expect(abs(slow.park.opacity.duration - 0.9) < 1e-9)
    }

    // MARK: Reduce Motion

    @Test func underReduceMotionEveryVariantIsAShortCrossfade() {
        for transition in PageTransition.allCases where transition != .current {
            let c = Self.choreography(transition, reducing: true)
            for look in [c.behind, c.front] {
                #expect(look.opacity == 0)
                #expect(look.x == 0 && look.y == 0 && look.scale == 1 && look.blur == 0)
                #expect(look.maskLeading == 0 && look.maskTrailing == 1)
            }
            #expect(c.flight == nil, "\(transition) flies under Reduce Motion")
            #expect(c.entrance == nil, "\(transition) staggers under Reduce Motion")
            #expect(!c.usesMask)
            #expect(c.longest <= 0.25)
            // Still a crossfade at a slowed pace, just slower.
            #expect(abs(Self.choreography(transition, speed: 0.1, reducing: true).longest - c.longest * 10) < 1e-9)
        }
        // Current keeps its own Reduce Motion: the same fades with no travel.
        let current = Self.choreography(.current, reducing: true)
        #expect(current.front.x == 0 && current.behind.x == 0)
        #expect(current.insert.opacity.duration == 0.2)
    }

    // MARK: Direction

    @Test func movesAreReadFromTheStack() {
        #expect(PageMove.between([], ["a"]) == .push)
        #expect(PageMove.between(["a"], ["a", "b"]) == .push)
        #expect(PageMove.between(["a", "b"], ["a"]) == .pop(levels: 1))
        #expect(PageMove.between(["a", "b", "c"], []) == .pop(levels: 3))
        #expect(PageMove.between(["a", "b", "c"], ["a"]) == .pop(levels: 2))
        #expect(PageMove.between(["a"], ["b"]) == .none)
        #expect(PageMove.between(["a"], ["a"]) == .none)
    }

    /// Push parks the page that was showing behind and brings the new one from the front; pop
    /// sends the top page back to the front and brings the one beneath back from behind. For
    /// the parallax push that's trailing in, leading out, and the reverse on pop.
    @Test func pushAndPopMoveEachPageTheRightWay() {
        let c = Self.choreography(.pushParallax)
        let push = c.pair(for: .push)!
        #expect(push.outgoing.look.x < 0)
        #expect(push.incoming.look.x > 0)
        #expect(push.outgoing.timing == c.park && push.incoming.timing == c.insert)
        let pop = c.pair(for: .pop(levels: 1))!
        #expect(pop.outgoing.look.x > 0)
        #expect(pop.incoming.look.x < 0)
        #expect(pop.outgoing.timing == c.remove && pop.incoming.timing == c.unpark)
        // Several levels at once animate the same two pages as one.
        #expect(c.pair(for: .pop(levels: 3)) == pop)
        #expect(c.pair(for: .none) == nil)

        let depth = Self.choreography(.scaleDepth)
        #expect(depth.pair(for: .push)!.outgoing.look.scale < 1 && depth.pair(for: .push)!.incoming.look.scale > 1)
        #expect(depth.pair(for: .pop(levels: 1))!.outgoing.look.scale > 1 && depth.pair(for: .pop(levels: 1))!.incoming.look.scale < 1)

        // The wipe sweeps trailing to leading on push: the arriving page is revealed from its
        // trailing side, the leaving one hidden from it.
        let wipe = Self.choreography(.maskedWipe)
        #expect(wipe.front.maskLeading == 1 && wipe.behind.maskTrailing == 0)
    }

    /// The complaint: going to a page and back weren't the same transition. Every staged variant
    /// treats a move by role, so a pop is a push mirrored: the page coming back (unpark) arrives
    /// exactly as a pushed page does (insert), and the page popped (remove) leaves exactly as the
    /// page beneath a push does (park), towards the far side. Root → Library → back, root →
    /// album → back and album → artist → back are all the same two roles, so this covers each.
    /// Current keeps its own timing (the page beneath always moves on pageExit).
    @Test func stagedVariantsMirrorPushAndPop() {
        for transition in PageTransition.allCases where transition != .current {
            for speed in [1, 0.1] {
                let c = Self.choreography(transition, speed: speed)
                let push = c.pair(for: .push)!, pop = c.pair(for: .pop(levels: 1))!
                #expect(pop.incoming.timing == push.incoming.timing, "\(transition) at \(speed)×: the page come back to arrives unlike a pushed one")
                #expect(pop.outgoing.timing == push.outgoing.timing, "\(transition) at \(speed)×: the popped page leaves unlike a parked one")
                // Mirrored in space: what a push sends behind, a pop brings back from behind.
                #expect(pop.incoming.look == push.outgoing.look && pop.outgoing.look == push.incoming.look)
            }
        }
    }

    // MARK: Double exposure

    /// The complaint: mid-transition both pages' text and covers show at once. Sampled at
    /// 240fps (as the recording was), the sequenced variants never have both pages above 5%
    /// opacity at the same moment, pushing or popping, at full speed or slowed.
    @Test func sequencedVariantsNeverShowBothPagesAtOnce() {
        let sequenced: [PageTransition] = [.sequencedFade, .scaleDepth, .heroMorph, .staggered, .blurCut]
        for transition in sequenced {
            for speed in [1, 0.1] {
                let c = Self.choreography(transition, speed: speed)
                for move in [PageMove.push, .pop(levels: 1)] {
                    var worst = 0.0
                    for frame in 0...Int((c.longest + 0.1) * 240) {
                        let o = c.opacities(for: move, at: Double(frame) / 240)!
                        worst = max(worst, min(o.outgoing, o.incoming))
                    }
                    #expect(worst < 0.05, "\(transition) \(move) at \(speed)×: both pages at \(worst)")
                }
                // And each one does finish: old page gone, new page fully there.
                let end = c.opacities(for: .push, at: c.longest * 3 + 1)!
                #expect(end.outgoing == 0 && end.incoming == 1)
            }
        }
    }

    /// The same sampling shows why the current hand-off reads as a double exposure.
    @Test func theCurrentHandOffOverlaps() {
        let c = Self.choreography(.current)
        let worst = (0...72).map { c.opacities(for: .push, at: Double($0) / 240)! }.map { min($0.outgoing, $0.incoming) }.max()!
        #expect(worst > 0.2)
    }

    /// The parallax page beneath is gone within a tenth of a second, so on glass, with no
    /// backing to slide over, nothing shows through the page sliding in.
    @Test func theParallaxPageBeneathIsGoneFast() {
        let c = Self.choreography(.pushParallax)
        for move in [PageMove.push, .pop(levels: 1)] {
            #expect(c.opacities(for: move, at: 0.1)!.outgoing == 0)
        }
    }

    /// The wipe shows each point of the column from one page only: the arriving page's mask
    /// and the leaving page's add up to one everywhere, at every frame.
    @Test func theWipesMasksAreComplementary() {
        let c = Self.choreography(.maskedWipe)
        let feather = c.maskFeather / 320
        for move in [PageMove.push, .pop(levels: 1)] {
            let pair = c.pair(for: move)!
            for frame in 0...Int(c.longest * 240) {
                let t = Double(frame) / 240
                let out = pair.outgoing.look.interpolated(pair.outgoing.timing.motion.progress(at: t))
                let into = pair.incoming.look.interpolated(1 - pair.incoming.timing.motion.progress(at: t))
                for u in stride(from: 0.0, through: 1.0, by: 0.05) {
                    let a = WipeMask.alpha(at: u, leading: out.maskLeading, trailing: out.maskTrailing, feather: feather)
                    let b = WipeMask.alpha(at: u, leading: into.maskLeading, trailing: into.maskTrailing, feather: feather)
                    #expect(abs(a + b - 1) < 1e-6, "\(move) at \(t)s, \(u)")
                }
            }
        }
    }

    @Test func aShownPageIsUnmaskedAndAHiddenOneFullyMasked() {
        let shown = WipeMask.stops(leading: 0, trailing: 1, feather: 0.1)
        #expect(shown.allSatisfy { $0.color == .black.opacity(1) })
        #expect(shown.first?.location == 0 && shown.last?.location == 1)
        let hidden = WipeMask.stops(leading: 1, trailing: 1, feather: 0.1)
        #expect(hidden.allSatisfy { $0.color == .black.opacity(0) })
    }

    // MARK: Staggered entry

    /// A pushed page's parts stagger in only while the push is fresh: a row built later (scrolled
    /// to, or loaded late) just appears.
    @Test func anEntranceIsFreshOnlyForItsWindow() {
        let plan = Self.choreography(.staggered).entrance!
        #expect(PageEntrance(plan: plan, startedAt: Date()).isFresh)
        #expect(!PageEntrance(plan: plan, startedAt: Date().addingTimeInterval(-plan.window - 0.01)).isFresh)
        // The window covers the last row's start, and grows with a slowed pace.
        #expect(plan.window > plan.phase(for: .row(plan.rowCap)).delay)
        #expect(Self.choreography(.staggered, speed: 0.1).entrance!.window > plan.window * 5)
    }

    /// A pushed page's parts come in one by one, and so do a page's come back to: popping (or
    /// opening a page further down, which pops back to it) stamps the page revealed, so going to
    /// a page and back are the same entrance.
    @Test func pushAndPopBothStampThePageThatComesIn() {
        let saved = UserDefaults.standard.data(forKey: "navigationState")
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: "navigationState") } else { UserDefaults.standard.removeObject(forKey: "navigationState") }
        }
        let navigation = NavigationModel()
        navigation.path = []
        // Opening from mini expands the app's own window; this model has nothing to expand.
        navigation.isMiniPlayer = false
        let album = BrowseItem(id: "MPREb_test", kind: .album, title: "Lateralus", subtitle: "Tool", artworkURL: nil)
        let artist = BrowseItem(id: "UC_test", kind: .artist, title: "Tool", subtitle: "Artist", artworkURL: nil)
        navigation.open(album)
        #expect(navigation.lastPushed?.id == album.id)
        navigation.open(artist)
        #expect(navigation.lastPushed?.id == artist.id)
        let stamped = navigation.lastPushed?.at
        navigation.pop()
        #expect(navigation.lastPushed?.id == album.id && navigation.lastPushed?.at != stamped)
        navigation.open(artist)
        // Re-opening a page further down pops back to it: the page revealed comes in.
        navigation.open(album)
        #expect(navigation.lastPushed?.id == album.id)
    }
}
