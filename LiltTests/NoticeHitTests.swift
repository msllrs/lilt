import AppKit
import SwiftUI
import Testing
@testable import Lilt

/// Clicking a notice: its Undo button runs the undo, anywhere else on it just dismisses it. The
/// capsule's own tap must not swallow the button's click. Hosted in an off-screen window and
/// clicked with synthetic events, as in ArtistLinkHitTests.
@MainActor
struct NoticeHitTests {
    private let size = CGSize(width: 320, height: 56)

    private func settle(_ frames: Int = 6) async {
        for _ in 0..<frames { try? await Task.sleep(for: .milliseconds(20)) }
    }

    private func click(_ point: CGPoint, in window: NSWindow) async {
        let location = CGPoint(x: point.x, y: window.frame.height - point.y)
        let number = Int(Date.timeIntervalSinceReferenceDate * 1000) % 1_000_000
        let time = ProcessInfo.processInfo.systemUptime
        let down = NSEvent.mouseEvent(with: .leftMouseDown, location: location, modifierFlags: [], timestamp: time, windowNumber: window.windowNumber, context: nil, eventNumber: number, clickCount: 1, pressure: 1)!
        let up = NSEvent.mouseEvent(with: .leftMouseUp, location: location, modifierFlags: [], timestamp: time + 0.05, windowNumber: window.windowNumber, context: nil, eventNumber: number + 1, clickCount: 1, pressure: 0)!
        window.sendEvent(down)
        await settle(1)
        window.sendEvent(up)
        await settle(2)
    }

    /// What a click at each point along the capsule's middle did: undone, dismissed, or nothing.
    private enum Outcome { case undone, dismissed, nothing }

    @Test func undoButtonUndoesAndTheRestDismisses() async throws {
        let center = NoticeCenter(clock: ManualNoticeClock())
        var undone = 0
        let notice = Notice(message: "Removed Schism", icon: .symbol("link"), action: .undo { undone += 1 })
        center.post(notice)
        let view = NoticeCapsule(notice: notice)
            .environment(center)
            .frame(width: size.width, height: size.height)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -10_000, y: -10_000), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        hosting.layoutSubtreeIfNeeded()
        await settle(8)

        var outcomes: [Outcome] = []
        for x in stride(from: CGFloat(4), through: size.width - 4, by: 4) {
            center.post(notice)
            let before = undone
            await click(CGPoint(x: x, y: size.height / 2), in: window)
            outcomes.append(undone > before ? .undone : center.current == nil ? .dismissed : .nothing)
        }
        #expect(outcomes.contains(.undone), "somewhere on the capsule is an Undo button that works")
        #expect(outcomes.contains(.dismissed), "clicking the rest of it dismisses it")
        // Left to right: nothing outside the capsule, the body dismissing, then the button.
        let firstUndo = try #require(outcomes.firstIndex(of: .undone))
        let firstDismiss = try #require(outcomes.firstIndex(of: .dismissed))
        #expect(firstDismiss < firstUndo, "the button sits after the message")
        #expect(outcomes.first == .nothing, "the space beside the capsule takes no clicks")
    }
}
