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

    /// A Scrubber `width` wide with the playhead at `at`, in an off-screen window. `editing`
    /// hears each value it reports, and whether that's the release.
    private func host(playheadAt at: Double, editing: @escaping (Double, Bool) -> Void) async -> NSWindow {
        let view = Scrubber(value: .constant(at), range: 0...length, onEditing: editing)
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
        let window = await host(playheadAt: at) { value, ended in if ended { landed.append(value) } }
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

    /// A mouse event of `type` at `x` along the line, halfway up it.
    private func mouse(_ type: NSEvent.EventType, atX x: CGFloat, in window: NSWindow) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: 6), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)!
    }

    /// A drag scrubs live, each step reported where the pointer is and not as the release, and
    /// the release reports where it let go. Picked up on the playhead, where a knob would be, it
    /// follows the pointer rather than an offset from where it was picked up.
    @Test func aDragScrubsLiveAndTheReleaseSeeks() async {
        var reports: [(value: Double, ended: Bool)] = []
        let window = await host(playheadAt: 160) { value, ended in reports.append((value, ended)) }
        defer { window.close() }
        let steps: [CGFloat] = [166, 200, 240]
        NSApp.postEvent(mouse(.leftMouseDown, atX: steps[0], in: window), atStart: false)
        for x in steps.dropFirst() { NSApp.postEvent(mouse(.leftMouseDragged, atX: x, in: window), atStart: false) }
        NSApp.postEvent(mouse(.leftMouseUp, atX: 240, in: window), atStart: false)
        await settle(2)

        let live = reports.filter { !$0.ended }.map(\.value)
        let released = reports.filter(\.ended).map(\.value)
        for x in steps {
            #expect(live.contains { abs($0 - Double(x)) <= 1 }, "a live report at \(x): \(live)")
        }
        #expect(released.count == 1, "one release: \(released)")
        #expect(abs((released.first ?? 0) - 240) <= 1, "released at 240, landed at \(released)")
        #expect(reports.last?.ended == true, "the release comes last")
    }
}
