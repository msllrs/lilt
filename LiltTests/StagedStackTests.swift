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
            return Color(red: 0, green: 0, blue: 1)
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
            let settle = Self.settled(choreography.unpark.opacity) + 0, motion = Self.settled(choreography.unpark.motion)
            let wait = max(settle, motion)
            try await Task.sleep(for: .seconds(wait + 0.6))
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
}
