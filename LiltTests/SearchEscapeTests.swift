import AppKit
import SwiftUI
import Testing
@testable import Lilt

/// Escape in the search field clears it, as it does in every search field on the Mac, so a
/// search is let go of with one key and the field is ready for the next.
@MainActor
struct SearchEscapeTests {
    private struct Field: View {
        @Bindable var navigation: NavigationModel
        var body: some View {
            SearchField(text: $navigation.query)
                .environment(navigation)
                .padding()
        }
    }

    @Test func escapeClearsTheQuery() async throws {
        // The navigation model persists every change to the shared defaults, which the real app
        // reads on its next launch; put them back as they were.
        let saved = UserDefaults.standard.data(forKey: "navigationState")
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: "navigationState") } else { UserDefaults.standard.removeObject(forKey: "navigationState") }
        }
        let navigation = NavigationModel()
        navigation.path = []
        navigation.query = "lateralus"
        let panel = PanelWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 320, height: 80))
        panel.contentView = NSHostingView(rootView: Field(navigation: navigation))
        panel.makeKeyAndOrderFront(nil)
        defer { panel.orderOut(nil); panel.close() }
        for _ in 0..<20 where !(panel.firstResponder is NSTextView) { try await Task.sleep(for: .milliseconds(20)) }
        // The test host isn't the active app, so focus may not have been handed over; put the
        // caret in the field as a click would.
        if !(panel.firstResponder is NSTextView), let field = Self.textField(in: panel.contentView) {
            panel.makeFirstResponder(field)
        }
        try #require(panel.firstResponder is NSTextView, "typing into the field")

        panel.sendEvent(Self.key(53, "\u{1b}", in: panel))
        for _ in 0..<20 where !navigation.query.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        #expect(navigation.query.isEmpty)
        #expect(panel.firstResponder is NSTextView, "the field keeps focus, ready for the next search")
    }

    private static func textField(in view: NSView?) -> NSTextField? {
        guard let view else { return nil }
        if let field = view as? NSTextField, field.isEditable { return field }
        return view.subviews.lazy.compactMap { textField(in: $0) }.first
    }

    private static func key(_ code: UInt16, _ characters: String, in window: NSWindow) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                         windowNumber: window.windowNumber, context: nil, characters: characters,
                         charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
    }
}
