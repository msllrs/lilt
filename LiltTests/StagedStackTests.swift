import AppKit
import SwiftUI
import Testing
@testable import Lilt

/// The staged stack (every variant but Current) hosted off screen with stand-in pages, driven
/// the way the column is: an observed path changing under it. (Swapping the hosting view's root
/// view instead cuts a removal short, so it can't show how long a popped page stays.)
@MainActor
struct StagedStackTests {
    @Observable final class Model { var path: [BrowseItem] = [] }

    /// What the stand-in pages did: how often each was evaluated, and when each went away.
    final class Log {
        var bodies: [String: Int] = [:]
        var gone: [String: Date] = [:]
    }

    /// A page's content: counts its evaluations and reads what a real page's discs, marquees
    /// and entrance items read, so it is invalidated whenever they would be.
    private struct Page: View {
        let key: String
        let log: Log
        @Environment(\.screenIsParked) private var parked
        @Environment(\.pageEntrance) private var entrance

        var body: some View {
            log.bodies[key, default: 0] += 1
            _ = (parked, entrance)
            return (key == PageSpace.searchKey ? Color(red: 1, green: 0, blue: 0) : Color(red: 0, green: 0, blue: 1))
                .onDisappear { log.gone[key] = Date() }
        }
    }

    private struct Host: View {
        let model: Model
        let choreography: PageChoreography
        let log: Log

        var body: some View {
            StagedStack(path: model.path, choreography: choreography, outOfSight: false) {
                Page(key: PageSpace.searchKey, log: log)
            } page: { item in
                Page(key: item.id, log: log)
            }
            .frame(width: 200, height: 100)
            .background(.white)
        }
    }

    private static let album = BrowseItem(id: "MPREb_test", kind: .album, title: "Lateralus", subtitle: "Tool", artworkURL: nil)
    private static let staged = PageTransition.allCases.filter { $0 != .current }

    private func host(_ model: Model, _ choreography: PageChoreography, _ log: Log) -> NSWindow {
        let hosting = NSHostingView(rootView: Host(model: model, choreography: choreography, log: log))
        hosting.frame = CGRect(x: 0, y: 0, width: 200, height: 100)
        let window = NSWindow(contentRect: CGRect(x: -10_000, y: -10_000, width: 200, height: 100), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderFrontRegardless()
        return window
    }

    /// When a phase has visibly finished: a spring runs on to its settling, not just its duration.
    private static func settled(_ phase: PagePhase) -> TimeInterval {
        phase.delay + (phase.curve == .spring ? Spring(duration: phase.duration, bounce: 0).settlingDuration : phase.duration)
    }

    /// A popped page is torn down (its rows, covers, scroll view) only once the page come back
    /// to has settled: letting it go while that page is still easing in costs the frames the
    /// easing needs. The popped page used to go at its own fade's end (0.09s for most variants)
    /// with the page beneath still arriving.
    @Test func aPoppedPageStaysUntilThePageComeBackToHasSettled() async throws {
        for transition in Self.staged {
            let choreography = PageChoreography.make(transition, dials: .defaults(for: transition), pace: MotionPace(speed: 0.25))
            let model = Model(), log = Log()
            let window = host(model, choreography, log)
            defer { window.close() }
            try await Task.sleep(for: .milliseconds(150))
            model.path = [Self.album]
            try await Task.sleep(for: .seconds(choreography.longest * 2 + 0.3))
            let popped = Date()
            model.path = []
            let wait = max(Self.settled(choreography.unpark.opacity), Self.settled(choreography.unpark.motion))
            // The hero morph's flight back can outlast the page come back to; the page waits for it.
            let flight = choreography.flight.map(Self.settled) ?? 0
            try await Task.sleep(for: .seconds(max(wait, flight) + 1.2))
            let gone = try #require(log.gone[Self.album.id], "\(transition): the popped page was never let go")
            let after = gone.timeIntervalSince(popped)
            #expect(after >= wait - 0.02, "\(transition): torn down \(after)s into the pop, the page come back to settles at \(wait)s")
        }
    }

    /// A popped page is left as it was while it leaves: nothing in it is evaluated again (its
    /// discs, marquees and entrance items stay as they are), as Current's removal leaves it.
    /// Re-evaluating it was a body pass over the whole leaving page on the pop's first frame.
    @Test func aPoppedPageIsLeftAloneAsItLeaves() async throws {
        for transition in Self.staged {
            let choreography = PageChoreography.make(transition, dials: .defaults(for: transition), pace: MotionPace(speed: 0.5))
            let model = Model(), log = Log()
            let window = host(model, choreography, log)
            defer { window.close() }
            try await Task.sleep(for: .milliseconds(150))
            model.path = [Self.album]
            try await Task.sleep(for: .seconds(choreography.longest + 0.3))
            let before = log.bodies[Self.album.id] ?? 0
            #expect(before >= 1)
            model.path = []
            try await Task.sleep(for: .seconds(choreography.longest * 2 + 0.5))
            #expect(log.bodies[Self.album.id] == before, "\(transition): the leaving page was evaluated \((log.bodies[Self.album.id] ?? 0) - before) more times")
        }
    }

    /// A page pushed again while it is still leaving comes back and stays, alone on top.
    @Test func aPagePushedAgainWhileLeavingComesBack() async throws {
        for transition in Self.staged {
            let choreography = PageChoreography.make(transition, dials: .defaults(for: transition), pace: MotionPace(speed: 0.5))
            let model = Model(), log = Log()
            let window = host(model, choreography, log)
            defer { window.close() }
            try await Task.sleep(for: .milliseconds(150))
            model.path = [Self.album]
            try await Task.sleep(for: .seconds(choreography.settled + 0.3))
            model.path = []
            try await Task.sleep(for: .seconds(choreography.remove.end / 2))
            model.path = [Self.album]
            try await Task.sleep(for: .seconds(choreography.settled * 2 + 0.6))
            let hosting = try #require(window.contentView)
            let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            let c = try #require(rep.colorAt(x: rep.pixelsWide / 2, y: rep.pixelsHigh / 2)?.usingColorSpace(.sRGB))
            // The page is blue, the root red, the background white: only the page shows.
            #expect(c.blueComponent > 0.5 && c.redComponent < 0.2, "\(transition): the page pushed back didn't stay (\(c))")
        }
    }
}
