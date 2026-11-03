import AppKit
import SwiftUI
import Testing
@testable import Lilt

/// The staged stack hosted off screen with pages that hold a real scroll view, as every screen
/// does, and its page layers read as a pop plays: where each page is and how faded, frame by
/// frame, as Core Animation is handed them. Stand-in pages of plain colour (StagedStackTests,
/// PageStageRenderTests) can't show either fault here, since both come from the AppKit views
/// and filters a real page has.
@MainActor
struct PageMotionRenderTests {
    @Observable final class Model { var path: [BrowseItem] = [] }
    private static let album = BrowseItem(id: "MPREb_test", kind: .album, title: "Lateralus", subtitle: "Tool", artworkURL: nil)
    private static let size = CGSize(width: 240, height: 360)

    /// A screen as the column has them: a scroll view of rows, which AppKit hosts as views of
    /// its own.
    private struct Screen: View {
        let hue: Double
        var body: some View {
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(0..<30, id: \.self) { i in
                        Text("Row \(i)").frame(maxWidth: .infinity, minHeight: 40).background(Color(hue: hue, saturation: 0.6, brightness: 0.8))
                    }
                }
            }
        }
    }

    private struct Stack: View {
        let model: Model
        let choreography: PageChoreography
        var body: some View {
            StagedStack(path: model.path, choreography: choreography, outOfSight: false) {
                Screen(hue: 0)
            } page: { _ in
                Screen(hue: 0.6)
            }
            .frame(width: PageMotionRenderTests.size.width, height: PageMotionRenderTests.size.height)
        }
    }

    /// One page layer at one moment.
    struct Sample { let t: Double; let opacity: Float; let x: CGFloat; let filtered: Bool }

    /// The layers SwiftUI gives each screen: the column-sized siblings nearest the top.
    private static func pages(in root: CALayer) -> [CALayer] {
        var level = [root]
        for _ in 0..<8 {
            let next: [CALayer] = level.flatMap { $0.sublayers ?? [] }
            let found: [CALayer] = next.filter { layer in
                let b = layer.bounds
                return abs(b.width - size.width) < 1 && abs(b.height - size.height) < 1
            }
            var parents: [ObjectIdentifier: [CALayer]] = [:]
            for layer in found {
                guard let parent = layer.superlayer else { continue }
                parents[ObjectIdentifier(parent), default: []].append(layer)
            }
            if let siblings = parents.values.first(where: { $0.count >= 2 }) { return siblings }
            level = next
        }
        return []
    }

    /// Pushes, waits, pops, and reads every page layer every couple of milliseconds for
    /// `seconds` after the pop. Returns each layer's samples, keyed by the layer.
    private func popTimeline(_ choreography: PageChoreography, seconds: Double) async throws -> [[Sample]] {
        let model = Model()
        let hosting = NSHostingView(rootView: Stack(model: model, choreography: choreography))
        hosting.frame = CGRect(origin: .zero, size: Self.size)
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -10_000, y: -10_000), size: Self.size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderFrontRegardless()
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(300))
        model.path = [Self.album]
        try await Task.sleep(for: .seconds(choreography.settled + 0.4))
        let root = try #require(hosting.layer)
        let t0 = CACurrentMediaTime()
        model.path = []
        var samples: [ObjectIdentifier: [Sample]] = [:]
        var order: [ObjectIdentifier] = []
        while CACurrentMediaTime() - t0 < seconds {
            let t = CACurrentMediaTime() - t0
            for layer in Self.pages(in: root) {
                let id = ObjectIdentifier(layer)
                if samples[id] == nil { order.append(id) }
                // Travel, whichever way SwiftUI hands it over: moved, or transformed.
                let x = layer.position.x - layer.bounds.width * layer.anchorPoint.x + layer.transform.m41
                samples[id, default: []].append(Sample(t: t, opacity: layer.opacity, x: x, filtered: !(layer.filters ?? []).isEmpty))
            }
            try await Task.sleep(for: .milliseconds(2))
        }
        return order.compactMap { samples[$0] }
    }

    /// The page popped: the one that starts shown and ends gone.
    private func leaving(_ timeline: [[Sample]]) -> [Sample]? {
        let end = timeline.compactMap { $0.last?.t }.max() ?? 0
        return timeline.first { s in
            guard let first = s.first, let last = s.last else { return false }
            return first.opacity > 0.99 && (last.opacity < 0.01 || last.t < end - 0.02)
        }
    }

    /// The popped page travels towards where pushed pages come from as it fades, over its
    /// motion's duration: on the first frame it has moved at all it is still near where it was,
    /// and it passes through several places on the way. It used to be the whole way over (12pt
    /// for the sequenced fade, 120pt for the parallax) on the first frame: `offset` moves a
    /// page's scroll view by its frame, which a scoped animation doesn't reach.
    @Test func aPoppedPageSlidesRatherThanJumps() async throws {
        for transition in [PageTransition.sequencedFade, .pushParallax, .blurSlide] {
            let choreography = PageChoreography.make(transition, dials: .defaults(for: transition), pace: MotionPace(speed: 0.5))
            let travel = choreography.front.x
            let timeline = try await popTimeline(choreography, seconds: choreography.remove.end + 0.5)
            let page = try #require(leaving(timeline), "\(transition): no page left")
            let moved = page.map(\.x).filter { abs($0) > 0.01 }
            let first = try #require(moved.first, "\(transition): the popped page never moved")
            #expect(abs(first) < abs(travel) / 2, "\(transition): \(first)pt of \(travel)pt on its first moved frame")
            let between = Set(moved.filter { abs($0) < abs(travel) - 0.5 }.map { Int($0 * 2) })
            #expect(between.count >= 3, "\(transition): only \(between.count) places between 0 and \(travel)pt")
        }
    }

    /// A page fading with a blur starts fading on time: no later after the pop's first frame
    /// than a page that only fades. Putting the blur on a live page (its scroll view and every
    /// row) held the frame back by a tenth of a second, the page standing still at full
    /// strength, and the page coming back waited as long again.
    @Test func aBlurredPageStartsFadingOnTime() async throws {
        func start(_ transition: PageTransition) async throws -> (first: Double, fading: Double, total: Double) {
            let choreography = PageChoreography.make(transition, dials: .defaults(for: transition))
            let timeline = try await popTimeline(choreography, seconds: 1)
            let page = try #require(leaving(timeline), "\(transition): no page left")
            // The pop's first frame: anything about any page changed.
            let firstChange = timeline.compactMap { s in s.first(where: { abs($0.opacity - s[0].opacity) > 0.001 || abs($0.x - s[0].x) > 0.01 })?.t }.min() ?? 0
            let fading = page.first { $0.opacity < 0.95 }?.t ?? 1
            let arrived = timeline.compactMap { s in (s.first?.opacity ?? 1) < 0.01 ? s.first(where: { $0.opacity > 0.99 })?.t : nil }.min() ?? 1
            return (firstChange, fading - firstChange, arrived)
        }
        let plain = try await start(.sequencedFade)
        for transition in [PageTransition.blurCut, .blurSlide] {
            let blurred = try await start(transition)
            #expect(blurred.fading < plain.fading + 0.04, "\(transition): the popped page began fading \(Int(blurred.fading * 1000))ms after the pop's first frame (a plain fade: \(Int(plain.fading * 1000))ms)")
            let designed = PageChoreography.make(transition, dials: .defaults(for: transition)).unpark.opacity.end
            #expect(blurred.total - blurred.first < designed + 0.12, "\(transition): the page come back to was fully in \(Int((blurred.total - blurred.first) * 1000))ms after the first frame; designed \(Int(designed * 1000))ms")
        }
    }
}
