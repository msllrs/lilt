import AppKit
import Testing
@testable import Lilt

/// Controls ▸ Shuffle and Repeat say what they will do, as the Dock menu's Shuffle does: the
/// menu bar is where ⌘⇧S and ⌘⇧R are learned, and pressed with the panel hidden nothing else
/// shows which mode they left you in.
@MainActor
struct ControlsMenuTests {
    @Test func shuffleAndRepeatAreNamedForWhatTheyWillDo() async throws {
        let player = try #require(AppDelegate.shared?.player, "the test host's own player, which the menu bar drives")
        func controls() -> NSMenu? { NSApp.mainMenu?.items.first { $0.title == "Controls" }?.submenu }
        try #require(controls() != nil, "a Controls menu")
        // Each change saves the queue to the shared defaults the real app reads on its next
        // launch; put it, and the player's modes, back as they were.
        let key = "playbackState"
        let playhead = SavedPlayhead()
        defer { playhead.restore() }
        let saved = UserDefaults.standard.data(forKey: key)
        let (shuffled, repeating) = (player.isShuffled, player.repeatMode)
        defer {
            if player.isShuffled != shuffled { player.toggleShuffle() }
            player.setRepeat(repeating)
            if let saved { UserDefaults.standard.set(saved, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
        }

        /// The menu as it reads when opened: SwiftUI brings a menu up to date as it opens.
        func titles() async -> [String] {
            for _ in 0..<5 { await Task.yield(); try? await Task.sleep(for: .milliseconds(20)) }
            guard let menu = controls() else { return [] }
            menu.delegate?.menuNeedsUpdate?(menu)
            menu.delegate?.menuWillOpen?(menu)
            menu.update()
            defer { menu.delegate?.menuDidClose?(menu) }
            return menu.items.map(\.title)
        }

        if player.isShuffled { player.toggleShuffle() }
        player.setRepeat(.off)
        var now = await titles()
        #expect(now.contains("Shuffle") && now.contains("Repeat All"), "\(now)")

        player.toggleShuffle()
        player.setRepeat(.all)
        now = await titles()
        #expect(now.contains("Stop Shuffling") && !now.contains("Shuffle"), "\(now)")
        #expect(now.contains("Repeat One"), "\(now)")

        player.setRepeat(.one)
        now = await titles()
        #expect(now.contains("Stop Repeating"), "\(now)")

        let shortcuts = (controls()?.items ?? []).filter { ["Stop Shuffling", "Stop Repeating"].contains($0.title) }.map(\.keyEquivalent)
        #expect(shortcuts == ["s", "r"], "the items keep ⌘⇧S and ⌘⇧R whatever they're called")
    }
}
