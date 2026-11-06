import AppKit
import SwiftUI
import Testing
@testable import Lilt

/// Clicking the platter's progress line jumps to the point clicked: the line runs edge to edge
/// with no knob, so where you click along it is where the song goes, at the ends and right
/// beside the playhead too.
@MainActor
@Suite(.serialized)
struct ScrubberClickTests {
    /// The line's width and the song's length, in points and seconds, so a click at x means x.
    private let width: CGFloat = 320
    private let length: Double = 320

    /// A Scrubber `width` wide with the playhead at `at`, in an off-screen window. `ended`
    /// collects each value a click lands on.
    private func host(playheadAt at: Double, ended: @escaping (Double) -> Void) async -> NSWindow {
        let view = Scrubber(value: .constant(at), range: 0...length, onEditing: { value, done in if done { ended(value) } })
            .frame(width: width, height: 12)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 12), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        window.orderFrontRegardless()
        window.contentView?.layoutSubtreeIfNeeded()
        await settle(2)
        return window
    }

    private func settle(_ turns: Int) async {
        for _ in 0..<turns { try? await Task.sleep(for: .milliseconds(20)) }
    }

    /// A click at `x` along the line, halfway up it. Both halves go through the app's event queue,
    /// as a real click does: the press is dispatched as the current event, so the scrubber reads
    /// it as a press, and the slider's own tracking loop then takes the release from the queue.
    private func click(atX x: CGFloat, in window: NSWindow) async {
        let location = CGPoint(x: x, y: 6)
        let number = Int(Date.timeIntervalSinceReferenceDate * 1000) % 1_000_000
        let time = ProcessInfo.processInfo.systemUptime
        let down = NSEvent.mouseEvent(with: .leftMouseDown, location: location, modifierFlags: [], timestamp: time, windowNumber: window.windowNumber, context: nil, eventNumber: number, clickCount: 1, pressure: 1)!
        let up = NSEvent.mouseEvent(with: .leftMouseUp, location: location, modifierFlags: [], timestamp: time + 0.05, windowNumber: window.windowNumber, context: nil, eventNumber: number + 1, clickCount: 1, pressure: 0)!
        NSApp.postEvent(down, atStart: false)
        NSApp.postEvent(up, atStart: false)
        await settle(2)
    }

    /// Where each click lands, with the playhead at `at`.
    private func landings(_ xs: [CGFloat], playheadAt at: Double) async -> [Double] {
        var landed: [Double] = []
        let window = await host(playheadAt: at) { landed.append($0) }
        defer { window.close() }
        for x in xs { await click(atX: x, in: window) }
        return landed
    }

    /// Within a point of where you clicked.
    private func expectLanded(_ landed: [Double], at xs: [CGFloat], _ why: String) {
        #expect(landed.count == xs.count, "every click lands (\(why))")
        for (value, x) in zip(landed, xs) {
            #expect(abs(value - Double(x)) <= 1, "clicked at \(x), landed at \(value) (\(why))")
        }
    }

    @Test func aClickAlongTheLineLandsWhereItWas() async {
        let xs: [CGFloat] = [40, 80, 240, 280]
        expectLanded(await landings(xs, playheadAt: 160), at: xs, "along the line")
    }

    /// The ends of the drawn line are the ends of the song: no dead half-knob at either end.
    @Test func theEndsOfTheLineAreTheEndsOfTheSong() async {
        let xs: [CGFloat] = [3, 8, 312, 317]
        expectLanded(await landings(xs, playheadAt: 160), at: xs, "near the ends")
    }

    /// Right beside the playhead there's no hidden knob to grab: the click jumps there too.
    @Test func aClickBesideThePlayheadJumpsToIt() async {
        let xs: [CGFloat] = [152, 156, 164, 168]
        expectLanded(await landings(xs, playheadAt: 160), at: xs, "beside the playhead")
    }
}
