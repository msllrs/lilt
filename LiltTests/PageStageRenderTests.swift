import AppKit
import SwiftUI
import Testing
@testable import Lilt

/// The staged stack rendered off screen and sampled as it animates: two stand-in pages, each
/// a solid square in its own half (the page shown first on the left, the pushed one on the
/// right), so one pixel in each half says how much of each page is showing at that moment.
/// Slowed to a tenth.
@MainActor
struct PageStageRenderTests {
    @Observable final class Model { var path: [BrowseItem] = [] }
    private static let album = BrowseItem(id: "MPREb_test", kind: .album, title: "Lateralus", subtitle: "Tool", artworkURL: nil)

    /// Driven by an observed path, as the column is: swapping the hosting view's root view
    /// instead cuts a removal short.
    private struct Stack: View {
        let model: Model
        let choreography: PageChoreography

        var body: some View {
            StagedStack(path: model.path, choreography: choreography, outOfSight: false) {
                page(Color(red: 1, green: 0, blue: 0), alignment: .leading)
            } page: { _ in
                page(Color(red: 0, green: 0, blue: 1), alignment: .trailing)
            }
            .frame(width: 200, height: 100)
            .background(.white)
        }

        private func page(_ color: Color, alignment: Alignment) -> some View {
            color.frame(width: 60, height: 60)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
                .padding(.horizontal, 20)
        }
    }

    /// How strongly each page shows, 0 (white) to its full strength, at its square's centre.
    private func sample(_ hosting: NSView) -> (red: Double, blue: Double) {
        let bounds = hosting.bounds
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: bounds) else { return (0, 0) }
        hosting.cacheDisplay(in: bounds, to: rep)
        func strength(atX x: Int) -> Double {
            guard let c = rep.colorAt(x: x * rep.pixelsWide / Int(bounds.width), y: rep.pixelsHigh / 2)?.usingColorSpace(.sRGB) else { return 0 }
            return 1 - Double(c.greenComponent)
        }
        return (strength(atX: 50), strength(atX: 150))
    }

    /// Off screen the window's updates arrive late and unevenly (one page's animation can wait
    /// for the other's), so this checks the mechanics, not the timing between the two pages:
    /// the pushed page fades in rather than cutting, the page beneath fades out and back, the
    /// popped page is kept while it fades out, and each ends where it should. The two pages
    /// never showing at once is checked on the timings themselves (PageTransitionTests).
    @Test func pushedAndPoppedPagesFadeRatherThanCut() async throws {
        // Not the variants that move their page off the sampled pixel (parallax, wipe). The
        // blur-through cut is in since its blur left the page for the veil over the stack: on the
        // page, off screen, it held the whole stack back by a second or more.
        for transition in [PageTransition.sequencedFade, .scaleDepth, .staggered, .heroMorph, .blurCut] {
            try await run(transition)
        }
    }

    private func run(_ transition: PageTransition) async throws {
        let choreography = PageChoreography.make(transition, dials: .defaults(for: transition), pace: MotionPace(speed: 0.1))
        let model = Model()
        let hosting = NSHostingView(rootView: Stack(model: model, choreography: choreography))
        hosting.frame = CGRect(x: 0, y: 0, width: 200, height: 100)
        let window = NSWindow(contentRect: CGRect(x: -10_000, y: -10_000, width: 200, height: 100), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderFrontRegardless()
        defer { window.close() }
        hosting.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(200))
        let full = sample(hosting)
        #expect(full.red > 0.5 && full.blue < 0.02)

        func run(pushed: Bool) async throws -> [(red: Double, blue: Double)] {
            model.path = pushed ? [Self.album] : []
            var frames: [(red: Double, blue: Double)] = []
            let start = Date()
            while Date().timeIntervalSince(start) < choreography.settled + 1 {
                try await Task.sleep(for: .milliseconds(15))
                frames.append(sample(hosting))
            }
            return frames
        }
        func fades(_ values: [Double]) -> Bool { values.contains { $0 > 0.1 && $0 < 0.9 } }

        let push = try await run(pushed: true)
        // Normalised to each page's own full strength (the colours come back through the
        // window's colour space, not as pure red and blue).
        let blueFull = push.last!.blue
        #expect(push.last!.red / full.red < 0.02 && blueFull > 0.5, "\(transition): push didn't land")
        #expect(fades(push.map { $0.blue / max(blueFull, 0.01) }), "\(transition): the pushed page cut in")
        #expect(fades(push.map { $0.red / full.red }), "\(transition): the page beneath cut out")

        let pop = try await run(pushed: false)
        #expect(pop.last!.red / full.red > 0.98 && pop.last!.blue / max(blueFull, 0.01) < 0.02, "\(transition): pop didn't land")
        #expect(fades(pop.map { $0.blue / max(blueFull, 0.01) }), "\(transition): the popped page cut out")
        #expect(fades(pop.map { $0.red / full.red }), "\(transition): the page beneath cut in")
    }
}
