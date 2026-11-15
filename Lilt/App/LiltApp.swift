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
            // ⌘R, as in Safari; ⌘⇧R is Repeat.
            CommandGroup(before: .toolbar) {
                Button("Refresh") { delegate.refresh() }
                    .keyboardShortcut("r", modifiers: .command)
                Divider()
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
                // Named for what they'll do, as the Dock menu's Shuffle is: pressed with the
                // panel hidden, nothing else shows which mode ⌘⇧S or ⌘⇧R left you in.
                Button(delegate.player.isShuffled ? "Stop Shuffling" : "Shuffle") { delegate.player.toggleShuffle() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                Button(Self.repeatTitle(after: delegate.player.repeatMode)) { delegate.player.cycleRepeat() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Divider()
                Picker("Sleep Timer", selection: Binding(get: { delegate.player.sleepTimer }, set: { delegate.player.setSleepTimer($0) })) {
                    Text("Off").tag(Duration?.none)
                    Text("15 Minutes").tag(Duration?.some(.seconds(15 * 60)))
                    Text("30 Minutes").tag(Duration?.some(.seconds(30 * 60)))
                    Text("1 Hour").tag(Duration?.some(.seconds(60 * 60)))
                }
                #if DEBUG
                Divider()
                Button("Tweak Artwork…") { delegate.showTweakPanel() }
                    .keyboardShortcut("t", modifiers: [.command, .option])
                #endif
            }
        }
    }

    /// The repeat item says the mode it moves on to.
    static func repeatTitle(after mode: PlayerService.RepeatMode) -> String {
        switch mode.next {
        case .all: "Repeat All"
        case .one: "Repeat One"
        case .off: "Stop Repeating"
        }
    }
}
