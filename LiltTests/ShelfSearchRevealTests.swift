import AppKit
import SwiftUI
import Testing
@testable import Lilt

/// A library shelf's page keeps its filter behind a search button at the top right, as Library
/// keeps its title: the button (or ⌘F) opens the field with the caret in it, and Escape in an
/// empty field folds it back to the button. A field with a filter in it stays open.
@MainActor
struct ShelfSearchRevealTests {
    private struct Host {
        let panel: PanelWindow
        let navigation: NavigationModel
    }

    private func host() async throws -> Host {
        let auth = AuthService()
        let music = YTMusicClient(auth: auth, persists: false, library: LibraryContent(albums: (1...3).map { BrowseItem(id: "MPREb-\($0)", kind: .album, title: "Album \($0)", subtitle: "Album • Tool") }), fetchAccount: { nil })
        let navigation = NavigationModel()
        navigation.path = [NavigationModel.library, LibraryShelf.albums.page]
        let view = LibraryShelfScreen(shelf: .albums, music: music)
            .environment(auth)
            .environment(PlayerService(auth: auth, makeBridge: { FakeBridge() }))
            .environment(music)
            .environment(navigation)
            .environment(ScrollTracker())
            .environment(CollapsedSections())
            .frame(width: 320, height: 400)
        let panel = PanelWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 320, height: 400))
        panel.contentView = NSHostingView(rootView: view)
        panel.makeKeyAndOrderFront(nil)
        try await Task.sleep(for: .milliseconds(200))
        return Host(panel: panel, navigation: navigation)
    }

    @Test func theFieldWaitsBehindTheSearchButton() async throws {
        let saved = UserDefaults.standard.data(forKey: "navigationState")
        defer { if let saved { UserDefaults.standard.set(saved, forKey: "navigationState") } else { UserDefaults.standard.removeObject(forKey: "navigationState") } }
        let host = try await host()
        defer { host.panel.orderOut(nil); host.panel.close() }
        #expect(Self.textField(in: host.panel.contentView) == nil, "no field until it's asked for")

        // The button sits in the header's trailing slot, under the panel's titlebar inset.
        let content = host.panel.contentView!
        click(CGPoint(x: content.bounds.width - Theme.Space.panelInset - Theme.Size.headerRow / 2, y: content.safeAreaInsets.top + Theme.Space.panelInset + Theme.Size.headerRow / 2), in: host.panel)
        for _ in 0..<25 where Self.textField(in: host.panel.contentView) == nil { try await Task.sleep(for: .milliseconds(20)) }
        let field = try #require(Self.textField(in: host.panel.contentView), "the button opens the field")
        // The field takes the caret itself: nothing here hands it over, as a click wouldn't.
        for _ in 0..<25 where !Self.isEditing(field, in: host.panel) { try await Task.sleep(for: .milliseconds(20)) }
        #expect(Self.isEditing(field, in: host.panel), "with the caret in it")

        host.panel.sendEvent(Self.key(53, "\u{1b}", in: host.panel))
        for _ in 0..<25 where Self.textField(in: host.panel.contentView) != nil { try await Task.sleep(for: .milliseconds(20)) }
        #expect(Self.textField(in: host.panel.contentView) == nil, "Escape in an empty field folds it away")
    }

    @Test func commandFOpensTheField() async throws {
        let saved = UserDefaults.standard.data(forKey: "navigationState")
        defer { if let saved { UserDefaults.standard.set(saved, forKey: "navigationState") } else { UserDefaults.standard.removeObject(forKey: "navigationState") } }
        let host = try await host()
        defer { host.panel.orderOut(nil); host.panel.close() }
        #expect(Self.textField(in: host.panel.contentView) == nil)
        _ = host.panel.performKeyEquivalent(with: Self.key(3, "f", modifiers: .command, in: host.panel))
        for _ in 0..<25 where Self.textField(in: host.panel.contentView) == nil { try await Task.sleep(for: .milliseconds(20)) }
        #expect(Self.textField(in: host.panel.contentView) != nil, "⌘F opens the field")
    }

    @Test func aFieldWithAFilterStaysOpen() async throws {
        let saved = UserDefaults.standard.data(forKey: "navigationState")
        defer { if let saved { UserDefaults.standard.set(saved, forKey: "navigationState") } else { UserDefaults.standard.removeObject(forKey: "navigationState") } }
        let host = try await host()
        defer { host.panel.orderOut(nil); host.panel.close() }
        _ = host.panel.performKeyEquivalent(with: Self.key(3, "f", modifiers: .command, in: host.panel))
        for _ in 0..<25 where Self.textField(in: host.panel.contentView) == nil { try await Task.sleep(for: .milliseconds(20)) }
        let field = try #require(Self.textField(in: host.panel.contentView))
        if !(host.panel.firstResponder is NSTextView) { host.panel.makeFirstResponder(field) }
        try #require(host.panel.firstResponder is NSTextView)
        (host.panel.firstResponder as? NSTextView)?.insertText("album 2", replacementRange: NSRange(location: NSNotFound, length: 0))
        try await Task.sleep(for: .milliseconds(100))

        // Clicking away from it, on the list.
        host.panel.makeFirstResponder(nil)
        try await Task.sleep(for: .milliseconds(200))
        #expect(Self.textField(in: host.panel.contentView) != nil, "the filter still applies, so the field stays")
    }

    private func click(_ point: CGPoint, in window: NSWindow) {
        let location = CGPoint(x: point.x, y: window.frame.height - point.y)
        let time = ProcessInfo.processInfo.systemUptime
        for (type, offset) in [(NSEvent.EventType.leftMouseDown, 0.0), (.leftMouseUp, 0.05)] {
            window.sendEvent(NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: time + offset, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)!)
        }
    }

    /// The field has the caret: the window's field editor is editing it.
    private static func isEditing(_ field: NSTextField, in window: NSWindow) -> Bool {
        (window.firstResponder as? NSTextView)?.delegate === field
    }

    private static func textField(in view: NSView?) -> NSTextField? {
        guard let view, !view.isHidden else { return nil }
        if let field = view as? NSTextField, field.isEditable { return field }
        return view.subviews.lazy.compactMap { textField(in: $0) }.first
    }

    private static func key(_ code: UInt16, _ characters: String, modifiers: NSEvent.ModifierFlags = [], in window: NSWindow) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: ProcessInfo.processInfo.systemUptime,
                         windowNumber: window.windowNumber, context: nil, characters: characters,
                         charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
    }
}
