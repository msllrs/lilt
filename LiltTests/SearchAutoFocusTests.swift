import AppKit
import SwiftUI
import Testing
@testable import Lilt

/// The search screen's field leaves the caret alone unless Settings ▸ General ▸ Focus search
/// automatically is on: arriving at it (opening the panel, or coming back from a page) doesn't
/// put the caret in it, so keys go to the panel's own shortcuts. On, it takes the caret as it
/// always did. A library shelf's filter, opened from its button, takes it either way.
///
/// On, the field asked for the caret as it appeared, before it was in a key window, and that
/// ask was dropped; its focus state still said focused, so the panel becoming key didn't ask
/// again. The same drop left a library shelf's filter, revealed by its button, without the
/// caret live.
@MainActor
struct SearchAutoFocusTests {
    /// `SearchField.autoFocusKey`, spelled out until the setting exists.
    static let autoFocusKey = "searchFocusesAutomatically"

    private struct Field: View {
        @Bindable var navigation: NavigationModel
        var body: some View {
            SearchField(text: $navigation.query)
                .environment(navigation)
                .padding()
        }
    }

    /// Whether the root field takes the caret by itself once it's on screen in a key panel.
    private func takesTheCaret(autoFocus: Bool?) async throws -> Bool {
        let savedNavigation = UserDefaults.standard.data(forKey: "navigationState")
        let savedSetting = UserDefaults.standard.object(forKey: Self.autoFocusKey)
        defer {
            if let savedNavigation { UserDefaults.standard.set(savedNavigation, forKey: "navigationState") } else { UserDefaults.standard.removeObject(forKey: "navigationState") }
            UserDefaults.standard.set(savedSetting, forKey: Self.autoFocusKey)
        }
        if let autoFocus { UserDefaults.standard.set(autoFocus, forKey: Self.autoFocusKey) } else { UserDefaults.standard.removeObject(forKey: Self.autoFocusKey) }
        let navigation = NavigationModel()
        navigation.path = []
        let panel = PanelWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 320, height: 80))
        panel.contentView = NSHostingView(rootView: Field(navigation: navigation))
        panel.makeKeyAndOrderFront(nil)
        defer { panel.orderOut(nil); panel.close() }
        // The panel becoming key again, as it does each time it's shown.
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: panel)
        for _ in 0..<20 where !(panel.firstResponder is NSTextView) { try await Task.sleep(for: .milliseconds(20)) }
        try await Task.sleep(for: .milliseconds(100))
        return panel.firstResponder is NSTextView
    }

    @Test func theSearchFieldWaitsToBeClickedByDefault() async throws {
        #expect(try await !takesTheCaret(autoFocus: nil), "nothing set: the caret stays out of the field")
        #expect(try await !takesTheCaret(autoFocus: false))
    }

    @Test func theSettingPutsTheCaretInIt() async throws {
        #expect(try await takesTheCaret(autoFocus: true))
    }
}
