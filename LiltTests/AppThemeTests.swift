import AppKit
import SwiftUI
import Testing
@testable import Lilt

/// Settings ▸ Appearance ▸ Theme: System, Light or Dark, for the whole app. It is set on
/// `NSApp.appearance`, so every window follows it, Settings' window style previews included.
@MainActor
@Suite(.serialized)
struct AppThemeTests {
    private func isolatedDefaults() -> UserDefaults {
        let suite = "AppThemeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func nothingStoredOrSomethingOddFollowsTheSystem() {
        let defaults = isolatedDefaults()
        #expect(AppTheme.stored(in: defaults) == .system)
        defaults.set("sepia", forKey: AppTheme.key)
        #expect(AppTheme.stored(in: defaults) == .system)
    }

    @Test func aStoredThemeComesBack() {
        let defaults = isolatedDefaults()
        AppTheme.dark.store(in: defaults)
        #expect(AppTheme.stored(in: defaults) == .dark)
        AppTheme.light.store(in: defaults)
        #expect(AppTheme.stored(in: defaults) == .light)
    }

    @Test func eachThemeIsAnAppearance() {
        #expect(AppTheme.system.appearance == nil)
        #expect(AppTheme.light.appearance?.name == .aqua)
        #expect(AppTheme.dark.appearance?.name == .darkAqua)
        #expect(AppTheme.allCases.map(\.label) == ["System", "Light", "Dark"])
    }

    /// The window style preview, as Settings shows it, draws in the chosen theme whatever the
    /// system is in, and goes back to following the system on System.
    @Test func thePreviewsFollowTheTheme() {
        let before = NSApp.appearance
        defer { NSApp.appearance = before }
        var seen: ColorScheme?
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = NSHostingView(rootView: SchemeProbe { seen = $0 })
        window.contentView = host

        for theme in [AppTheme.dark, .light, .dark] {
            theme.apply()
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            host.layoutSubtreeIfNeeded()
            #expect(seen == (theme == .dark ? .dark : .light), "\(theme)")
        }
        AppTheme.system.apply()
        #expect(NSApp.appearance == nil)
    }
}

private struct SchemeProbe: View {
    var report: (ColorScheme) -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        WindowStylePreview(style: WindowStyle.standard, accent: nil)
            .onAppear { report(colorScheme) }
            .onChange(of: colorScheme) { report(colorScheme) }
    }
}
