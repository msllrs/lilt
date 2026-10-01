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
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .windowList) {
                Button("Show Lilt") { delegate.showPanel() }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                Button("Hide Lilt") { delegate.hidePanel() }
                    .keyboardShortcut("w", modifiers: .command)
                #if DEBUG
                Divider()
                Button("Tweak Artwork…") { delegate.showTweakPanel() }
                    .keyboardShortcut("t", modifiers: [.command, .option])
                #endif
            }
        }
    }
}
