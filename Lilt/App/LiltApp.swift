import SwiftUI

@main
struct LiltApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // The panel itself is AppKit-owned (see AppDelegate) so it can hide instead of close.
        // This scene provides the standard menu bar and a small settings window.
        Settings {
            SettingsView()
                .environment(delegate.auth)
                .environment(delegate.player)
                .environment(delegate.music)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { delegate.updater.checkForUpdates(nil) }
            }
            CommandGroup(after: .windowList) {
                Button("Show Lilt") { delegate.showPanel() }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                Button("Hide Lilt") { delegate.hidePanel() }
                    .keyboardShortcut("w", modifiers: .command)
                Button("Mini Player") { delegate.toggleMiniPlayer() }
                    .keyboardShortcut("m", modifiers: [.command, .shift])
                Button("Library") { delegate.openLibrary() }
                    .keyboardShortcut("l", modifiers: .command)
            }
            // Transport, as in Music: Space (when not typing), ⌘→ and ⌘←. The panel handles
            // the keys itself too, so they work while another app is frontmost.
            CommandMenu("Controls") {
                Button(delegate.player.isPlaying ? "Pause" : "Play") { delegate.player.togglePlayPause() }
                    .keyboardShortcut(.space, modifiers: [])
                    .disabled(delegate.player.current == nil)
                Button("Next") { delegate.player.next() }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
                    .disabled(!delegate.player.hasNext)
                Button("Previous") { delegate.player.previous() }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                    .disabled(delegate.player.current == nil)
                Divider()
                Button("Shuffle") { delegate.player.toggleShuffle() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                Button("Repeat") { delegate.player.cycleRepeat() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                #if DEBUG
                Divider()
                Button("Tweak Artwork…") { delegate.showTweakPanel() }
                    .keyboardShortcut("t", modifiers: [.command, .option])
                #endif
            }
        }
    }
}
