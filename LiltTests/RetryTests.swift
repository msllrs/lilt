import AppKit
import SwiftUI
import Testing
@testable import Lilt

/// A screen that couldn't load offers to try again where it says so, rather than leaving ⌘R
/// as the only way back (and a failed search with none, short of editing the query). The
/// library stands in: offline for its first attempt, back for the second.
@MainActor
struct RetryTests {
    private static let size = CGSize(width: 320, height: 600)

    @Test func aLibraryThatFailedLoadsAgainFromItsButton() async throws {
        var online = false
        var fetches = 0
        let auth = AuthService()
        let music = YTMusicClient(auth: auth, fetchPage: { _ in
            fetches += 1
            guard online else { throw URLError(.notConnectedToInternet) }
            return JSONObject(value: [:])
        }, persists: false, fetchAccount: { nil })
        let view = LibraryScreen(music: music)
            .environment(auth)
            .environment(PlayerService(auth: auth, makeBridge: { FakeBridge() }))
            .environment(music)
            .environment(NavigationModel())
            .environment(ScrollTracker())
            .environment(CollapsedSections())
            .frame(width: Self.size.width, height: Self.size.height)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(origin: .zero, size: Self.size)
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -10_000, y: -10_000), size: Self.size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderFrontRegardless()
        defer { window.close() }

        await settle(until: { fetches == 4 })
        try await Task.sleep(for: .milliseconds(200))
        #expect(fetches == 4, "one attempt: the library's four feeds")

        online = true
        // The button sits under the message in the middle of the screen; click down the
        // middle until one lands.
        for y in stride(from: 200.0, through: 440, by: 8) where fetches == 4 {
            click(CGPoint(x: Self.size.width / 2, y: y), in: window)
            try await Task.sleep(for: .milliseconds(60))
        }
        await settle(until: { fetches == 8 })
        #expect(fetches == 8, "Try Again fetches the library again")
    }

    /// A click at `point`, in SwiftUI's coordinates (origin top-left).
    private func click(_ point: CGPoint, in window: NSWindow) {
        let location = CGPoint(x: point.x, y: window.frame.height - point.y)
        let time = ProcessInfo.processInfo.systemUptime
        for (type, offset) in [(NSEvent.EventType.leftMouseDown, 0.0), (.leftMouseUp, 0.05)] {
            let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: time + offset, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)!
            window.sendEvent(event)
        }
    }

    private func settle(until done: () -> Bool) async {
        for _ in 0..<100 where !done() { try? await Task.sleep(for: .milliseconds(20)) }
    }
}
