import AppKit
import SwiftUI
import Testing
@testable import Lilt

/// The playhead moves twice a second for as long as music plays. Each move rebuilds the elapsed
/// time and the line, and nothing else of the platter: not the palette it works out from the
/// cover, and nothing at all while the panel is out of sight.
@MainActor
@Suite(.serialized)
struct PlatterTickTests {
    private func song(_ id: String) -> Track { Track(id: id, title: id, artist: "Tool") }

    /// The platter on `player`, in an off-screen window, parked or not as the panel out of sight
    /// parks it. The navigation model's saved state is put back on close.
    private func host(_ player: PlayerService, parked: Bool) async -> (NSWindow, NSView) {
        let auth = AuthService()
        let saved = UserDefaults.standard.data(forKey: "navigationState")
        let navigation = NavigationModel()
        navigation.path = []
        navigation.isMiniPlayer = false
        if let saved { UserDefaults.standard.set(saved, forKey: "navigationState") } else { UserDefaults.standard.removeObject(forKey: "navigationState") }
        let view = NowPlayingBar()
            .environment(\.screenIsParked, parked)
            .environment(auth)
            .environment(player)
            .environment(YTMusicClient(auth: auth))
            .environment(navigation)
            .environment(ScrollTracker())
            .frame(width: 320, height: 170)
        let hosting = NSHostingView(rootView: AnyView(view))
        hosting.frame = CGRect(x: 0, y: 0, width: 320, height: 170)
        let window = NSWindow(contentRect: CGRect(x: -10_000, y: -10_000, width: 320, height: 170), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderFrontRegardless()
        await settle(hosting)
        return (window, hosting)
    }

    private func settle(_ hosting: NSView, _ turns: Int = 6) async {
        for _ in 0..<turns {
            try? await Task.sleep(for: .milliseconds(20))
            hosting.layoutSubtreeIfNeeded()
        }
    }

    /// The palettes worked out and playheads built over ten ticks of the clock.
    private func overTenTicks(parked: Bool) async throws -> (palettes: Int, playheads: Int) {
        var counts = (palettes: 0, playheads: 0)
        try await withFakePlayer(["grudge", "eon"].map(song), gapless: false) { player, fakes in
            fakes.startPlaying(player)
            let (window, hosting) = await host(player, parked: parked)
            defer { window.close() }
            let id = ObjectIdentifier(player)
            PlatterBuildCounts.palettes[id] = 0
            PlatterBuildCounts.playheads[id] = 0
            for tick in 1...10 {
                fakes.first.report("grudge", time: 1 + Double(tick) / 2)
                await settle(hosting, 2)
            }
            #expect(player.currentTime == 6)
            counts = (PlatterBuildCounts.palettes[id] ?? 0, PlatterBuildCounts.playheads[id] ?? 0)
            PlatterBuildCounts.palettes[id] = nil
            PlatterBuildCounts.playheads[id] = nil
        }
        return counts
    }

    @Test func theClockRebuildsThePlayheadAlone() async throws {
        let counts = try await overTenTicks(parked: false)
        #expect(counts.palettes == 0, "the palette was worked out \(counts.palettes) times for the clock")
        #expect(counts.playheads >= 10, "the playhead followed the clock \(counts.playheads) times")
    }

    @Test func outOfSightTheClockRebuildsNothing() async throws {
        let counts = try await overTenTicks(parked: true)
        #expect(counts.palettes == 0, "the palette was worked out \(counts.palettes) times out of sight")
        #expect(counts.playheads == 0, "the playhead was built \(counts.playheads) times out of sight")
    }
}
