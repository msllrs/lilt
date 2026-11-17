import Foundation
import Testing
@testable import Lilt

/// Lilt's own Now Playing entry, there between a relaunch and the first play, carries the elapsed
/// time, so the bridge that publishes it follows the clock. Once the web page's session is the
/// entry there's nothing of Lilt's to keep up to date, and the playhead moving twice a second
/// shouldn't have it look at the player again each time.
@MainActor
struct RemoteCommandTickTests {
    private let songs = [Track(id: "schism", title: "Schism", artist: "Tool"), Track(id: "parabola", title: "Parabola", artist: "Tool")]

    private func settle() async {
        for _ in 0..<3 { await Task.yield() }
    }

    @Test func withTheWebSessionTheClockIsNotFollowed() async throws {
        try await withFakePlayer(songs, gapless: false) { player, fakes in
            let bridge = RemoteCommandBridge(player: player)
            fakes.startPlaying(player)
            await settle()
            #expect(player.hasWebSession)
            let before = bridge.updates
            for tick in 1...10 {
                fakes.first.report("schism", time: 1 + Double(tick) / 2)
                await settle()
            }
            #expect(bridge.updates - before == 0, "\(bridge.updates - before) updates for ten ticks")
        }
    }

    /// Restored and not yet played, Lilt's own entry is up and still follows a seek.
    @Test func liltsOwnEntryStillFollowsTheClock() async throws {
        try await withFakePlayer(songs, gapless: false) { player, _ in
            let bridge = RemoteCommandBridge(player: player)
            await settle()
            #expect(!player.hasWebSession)
            let before = bridge.updates
            player.seek(to: 30)
            await settle()
            #expect(bridge.updates > before)
        }
    }
}
