import AppKit
import Observation
import SwiftUI
import Testing
@testable import Lilt

/// The playing track's disc turns in Core Animation, not in SwiftUI: the picture's layer carries
/// one repeating rotation while the disc spins and a plain transform while it rests, so the view
/// graph only hears about a start, a stop or a new cover. Driven by a `TimelineView`, every
/// thirtieth of a second re-ran tens of thousands of graph updates and a layout of the window.
@MainActor
struct DiscSpinTests {
    private static let dps = SpinningArtwork.degreesPerSecond

    private static func cover(_ hue: CGFloat = 0.6) -> NSImage {
        NSImage(size: NSSize(width: 240, height: 240), flipped: false) { rect in
            NSColor(hue: hue, saturation: 0.7, brightness: 0.8, alpha: 1).setFill()
            rect.fill()
            return true
        }
    }

    private static func view() -> SpinningPictureView {
        let view = SpinningPictureView(frame: NSRect(x: 0, y: 0, width: 40, height: 40))
        view.show(cover(), scale: 2)
        return view
    }

    /// Clockwise degrees, as the layer's own (y-up, so negated) radians.
    private static func radians(_ degrees: Double) -> Double { -degrees * .pi / 180 }

    private static func modelRadians(view: SpinningPictureView) -> Double { modelRadians(view) }

    private static func modelRadians(_ view: SpinningPictureView) -> Double {
        (view.picture.value(forKeyPath: "transform.rotation.z") as? Double) ?? .nan
    }

    // MARK: The layer

    @Test func aSpinningDiscTurnsInCoreAnimation() throws {
        let view = Self.view()
        let now = Date.now
        view.apply(ArtworkSpin(baseAngle: 30, resumedAt: now.addingTimeInterval(-1), degreesPerSecond: Self.dps, paused: false), at: now)
        let turn = try #require(view.picture.animation(forKey: SpinningPictureView.spinKey) as? CABasicAnimation)
        #expect(turn.keyPath == "transform.rotation.z")
        #expect(turn.repeatCount == .infinity)
        #expect(turn.duration == 8)
        // From where the clock says it is now (30° plus a second's 45°), a full turn clockwise.
        #expect(abs((turn.fromValue as! Double) - Self.radians(75)) < 1e-9)
        #expect(abs((turn.byValue as! Double) + 2 * .pi) < 1e-9)
    }

    /// A turn of 45° a second moves under a degree and a half a frame at 30 Hz, which looks as
    /// smooth as 120 Hz, and an uncapped animation has the window server recomposite the whole
    /// panel, its blurs and glass included, at the display's full rate for as long as music plays.
    @Test func theTurnAsksForThirtyFramesASecond() throws {
        let view = Self.view()
        let now = Date.now
        view.apply(ArtworkSpin(baseAngle: 0, resumedAt: now, degreesPerSecond: Self.dps, paused: false), at: now)
        let turn = try #require(view.picture.animation(forKey: SpinningPictureView.spinKey) as? CABasicAnimation)
        #expect(turn.preferredFrameRateRange.maximum == 30)
        #expect(turn.preferredFrameRateRange.preferred == 30)
        #expect(turn.preferredFrameRateRange.minimum == 15)
    }

    @Test func pausingHoldsTheAngle() {
        let view = Self.view()
        let start = Date.now
        view.apply(ArtworkSpin(baseAngle: 10, resumedAt: start, degreesPerSecond: Self.dps, paused: false), at: start)
        // What SpinningArtwork does on pause two seconds later: fold the elapsed turn in.
        view.apply(ArtworkSpin(baseAngle: 100, resumedAt: nil, degreesPerSecond: Self.dps, paused: true), at: start.addingTimeInterval(2))
        #expect(view.picture.animationKeys() == nil)
        #expect(abs(Self.modelRadians(view) - Self.radians(100)) < 1e-9)
        #expect(abs(view.displayedDegrees - 100) < 1e-6)
    }

    /// A parked screen keeps its clock but stops the picture where it is.
    @Test func parkingHoldsTheAngleTheClockShows() {
        let view = Self.view()
        let start = Date.now
        let spin = ArtworkSpin(baseAngle: 0, resumedAt: start, degreesPerSecond: Self.dps, paused: false)
        view.apply(spin, at: start)
        var parked = spin
        parked.paused = true
        view.apply(parked, at: start.addingTimeInterval(1))
        #expect(view.picture.animationKeys() == nil)
        #expect(abs(view.displayedDegrees - 45) < 1e-6)
    }

    @Test func resumingStartsFromTheHeldAngle() throws {
        let view = Self.view()
        let now = Date.now
        view.apply(ArtworkSpin(baseAngle: 120, resumedAt: nil, degreesPerSecond: Self.dps, paused: true), at: now)
        view.apply(ArtworkSpin(baseAngle: 120, resumedAt: now, degreesPerSecond: Self.dps, paused: false), at: now)
        let turn = try #require(view.picture.animation(forKey: SpinningPictureView.spinKey) as? CABasicAnimation)
        #expect(abs((turn.fromValue as! Double) - Self.radians(120)) < 1e-9)
    }

    @Test func aNewCoverLeavesTheTurnAlone() throws {
        let view = Self.view()
        let spin = ArtworkSpin(baseAngle: 0, resumedAt: .now, degreesPerSecond: Self.dps, paused: false)
        view.apply(spin)
        let before = try #require(view.picture.animation(forKey: SpinningPictureView.spinKey))
        view.show(Self.cover(0.1), scale: 2)
        view.apply(spin)
        let after = try #require(view.picture.animation(forKey: SpinningPictureView.spinKey))
        #expect(after.beginTime == before.beginTime)
        #expect(view.picture.contents != nil)
    }

    /// Back to artwork, the picture eases upright from where it is, never the long way round,
    /// whichever of 0° and 360° it is told to rest at.
    @Test(arguments: [(300.0, 360.0, 60.0), (100.0, 0.0, 100.0), (100.0, 360.0, 100.0), (300.0, 0.0, 60.0)])
    func settlingGoesUprightTheShorterWay(held: Double, rest: Double, travel: Double) throws {
        let view = Self.view()
        view.apply(ArtworkSpin(baseAngle: held, resumedAt: nil, degreesPerSecond: Self.dps, paused: true))
        view.apply(ArtworkSpin(baseAngle: rest, resumedAt: nil, degreesPerSecond: Self.dps, paused: true))
        let settle = try #require(view.picture.animation(forKey: SpinningPictureView.spinKey) as? CAKeyframeAnimation)
        let values = try #require(settle.values as? [Double])
        let first = try #require(values.first), last = try #require(values.last)
        #expect(abs(abs(first - last) - travel * .pi / 180) < 1e-9)
        #expect(abs(last - Self.radians(rest)) < 1e-9)
        #expect(abs(first - last) < .pi)
        // The model is already upright, so the end of the animation leaves it there.
        #expect(abs(Self.modelRadians(view).truncatingRemainder(dividingBy: 2 * .pi)) < 1e-9)
    }

    // MARK: In SwiftUI

    @Observable final class Disc {
        var isDisc: Bool
        var isSpinning: Bool
        /// Settings ▸ Appearance off, or Reduce Motion on.
        var holdsStill = false
        init(isDisc: Bool, isSpinning: Bool) { self.isDisc = isDisc; self.isSpinning = isSpinning }
    }

    private struct Harness: View {
        let disc: Disc
        let url: URL
        var tapped: () -> Void = {}
        var body: some View {
            Button(action: tapped) {
                SpinningArtwork(url: url, size: 40, restRadius: 8, isDisc: disc.isDisc, isSpinning: disc.isSpinning)
            }
            .buttonStyle(.plain)
            .frame(width: 120, height: 120)
            .environment(\.discsHoldStill, disc.holdsStill)
        }
    }

    private static func cachedCoverURL() -> URL {
        let url = URL(string: "https://lh3.googleusercontent.com/test-disc-spin-cover=w240-h240-l90-rj")!
        if ImageCache.shared.cached(url) == nil { ImageCache.shared.store(cover(), for: url) }
        return url
    }

    /// Counts the hosting view's layout passes: each tick of the old clock ran one.
    private final class CountingHostingView<Content: View>: NSHostingView<Content> {
        var layouts = 0
        override func layout() {
            layouts += 1
            super.layout()
        }
    }

    /// Small and all but transparent at the screen's corner: on screen as far as the window
    /// server's display link is concerned, so animation clocks really tick.
    private func window<Content: View>(_ hosting: CountingHostingView<Content>) -> NSWindow {
        hosting.frame = NSRect(x: 0, y: 0, width: 120, height: 120)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.alphaValue = 0.02
        window.contentView = hosting
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        return window
    }

    private func settle(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    private static func pictures(in view: NSView) -> [SpinningPictureView] {
        view.subviews.flatMap { ($0 as? SpinningPictureView).map { [$0] } ?? pictures(in: $0) }
    }

    @Test func plainArtworkStaysASwiftUIImage() async {
        let hosting = CountingHostingView(rootView: Harness(disc: Disc(isDisc: false, isSpinning: false), url: Self.cachedCoverURL()))
        let window = window(hosting)
        defer { window.close() }
        await settle(0.1)
        #expect(Self.pictures(in: hosting).isEmpty)
    }

    @Test func theDiscSpinsPausesAndSettlesBackToArtwork() async throws {
        let disc = Disc(isDisc: true, isSpinning: true)
        let hosting = CountingHostingView(rootView: Harness(disc: disc, url: Self.cachedCoverURL()))
        let window = window(hosting)
        defer { window.close() }
        await settle(0.3)
        let picture = try #require(Self.pictures(in: hosting).first)
        #expect(picture.picture.animation(forKey: SpinningPictureView.spinKey) is CABasicAnimation)
        // Turning clockwise, in the render server's time: a little past upright already.
        #expect(picture.displayedDegrees > 5 && picture.displayedDegrees < 45)

        disc.isSpinning = false
        await settle(0.1)
        #expect(picture.picture.animationKeys() == nil)
        let held = picture.displayedDegrees
        await settle(0.2)
        #expect(picture.displayedDegrees == held)

        disc.isDisc = false
        await settle(0.05)
        #expect(picture.picture.animation(forKey: SpinningPictureView.spinKey) is CAKeyframeAnimation)
        // Once upright, the plain image takes over again.
        await settle(0.8)
        #expect(Self.pictures(in: hosting).isEmpty)
    }

    /// Spinning off in Settings, or Reduce Motion: the playing song's cover stays a disc but
    /// settles upright and rests there; let go, it turns again from upright.
    @Test func aDiscHeldStillRestsUpright() async throws {
        let disc = Disc(isDisc: true, isSpinning: true)
        let hosting = CountingHostingView(rootView: Harness(disc: disc, url: Self.cachedCoverURL()))
        let window = window(hosting)
        defer { window.close() }
        await settle(0.6)
        let picture = try #require(Self.pictures(in: hosting).first)
        #expect(picture.displayedDegrees > 10)

        disc.holdsStill = true
        await settle(0.1)
        #expect(Self.pictures(in: hosting).first === picture, "no longer a disc")
        // Not turning: at most the ease back upright, which ends where the model already rests.
        #expect(!(picture.picture.animation(forKey: SpinningPictureView.spinKey) is CABasicAnimation))
        #expect(abs(Self.modelRadians(view: picture).truncatingRemainder(dividingBy: 2 * .pi)) < 1e-9)

        disc.holdsStill = false
        await settle(0.3)
        #expect(picture.picture.animation(forKey: SpinningPictureView.spinKey) is CABasicAnimation)
        #expect(picture.displayedDegrees > 5 && picture.displayedDegrees < 45)
    }

    /// The disc is the label of the row's play/pause button; the layer under it mustn't take the
    /// click for itself.
    @Test func clickingTheSpinningDiscStillPressesItsButton() async throws {
        var taps = 0
        let hosting = CountingHostingView(rootView: Harness(disc: Disc(isDisc: true, isSpinning: true), url: Self.cachedCoverURL(), tapped: { taps += 1 }))
        let window = window(hosting)
        defer { window.close() }
        await settle(0.2)
        #expect(!Self.pictures(in: hosting).isEmpty)
        // The disc's label, off the hole in its middle.
        let location = CGPoint(x: 60 + 12, y: 60)
        let number = Int(Date.timeIntervalSinceReferenceDate * 1000) % 1_000_000
        let time = ProcessInfo.processInfo.systemUptime
        let down = NSEvent.mouseEvent(with: .leftMouseDown, location: location, modifierFlags: [], timestamp: time, windowNumber: window.windowNumber, context: nil, eventNumber: number, clickCount: 1, pressure: 1)!
        let up = NSEvent.mouseEvent(with: .leftMouseUp, location: location, modifierFlags: [], timestamp: time + 0.05, windowNumber: window.windowNumber, context: nil, eventNumber: number + 1, clickCount: 1, pressure: 0)!
        window.sendEvent(down)
        await settle(0.02)
        window.sendEvent(up)
        await settle(0.05)
        #expect(taps == 1)
    }

    // MARK: Cost

    /// What the disc used to be: the picture rotated by a clock at thirty frames a second.
    private struct TimelineDisc: View {
        let image: NSImage
        let start: Date
        let ticked: () -> Void
        var body: some View {
            TimelineView(.animation(minimumInterval: 1 / 30, paused: false)) { context in
                let _ = ticked()
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                    .frame(width: 40, height: 40)
                    .rotationEffect(.degrees(context.date.timeIntervalSince(start) * 45))
            }
            .clipShape(Circle())
            .frame(width: 120, height: 120)
        }
    }

    /// Half a second of a spinning disc: the old clock re-ran its content and laid out the window
    /// every frame; the Core Animation disc lays out nothing once it is going.
    @Test func aSpinningDiscCostsSwiftUINothingPerFrame() async throws {
        var ticks = 0
        let old = CountingHostingView(rootView: TimelineDisc(image: Self.cover(), start: .now, ticked: { ticks += 1 }))
        let oldWindow = window(old)
        await settle(0.2)
        let (oldTicks, oldLayouts) = (ticks, old.layouts)
        await settle(0.5)
        let oldPerHalfSecond = (ticks: ticks - oldTicks, layouts: old.layouts - oldLayouts)
        oldWindow.close()

        let new = CountingHostingView(rootView: Harness(disc: Disc(isDisc: true, isSpinning: true), url: Self.cachedCoverURL()))
        let newWindow = window(new)
        defer { newWindow.close() }
        await settle(0.2)
        let picture = try #require(Self.pictures(in: new).first)
        let (startDegrees, startLayouts) = (picture.displayedDegrees, new.layouts)
        await settle(0.5)
        let newLayouts = new.layouts - startLayouts
        let turned = picture.displayedDegrees - startDegrees

        print("DiscSpin over 0.5s: TimelineView disc \(oldPerHalfSecond.ticks) content runs, \(oldPerHalfSecond.layouts) window layouts; Core Animation disc \(newLayouts) window layouts while turning \(String(format: "%.1f", turned))°")
        #expect(oldPerHalfSecond.layouts > 5)
        #expect(newLayouts == 0)
        // It really was turning meanwhile: about 22.5° in half a second.
        #expect(turned > 15 && turned < 30)
    }
}
