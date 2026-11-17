import AppKit
import SwiftUI
import Testing
@testable import Lilt

/// Live, the shelf filter's button opened the field without the caret in it. The log showed why:
/// the search screen's field, parked beneath the shelf's page, took the caret instead, and the
/// filter, seeing a field editor at work, took it for its own and stopped asking. And a field
/// only took the caret when its placeholder text was clicked, not the rest of it.
@MainActor
struct ShelfFilterCaretTests {
    private func saved<T>(_ body: () async throws -> T) async rethrows -> T {
        let keys = ["navigationState", "playbackState", PlayerService.playheadKey]
        let saved = keys.map { UserDefaults.standard.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, saved) {
                if let value { UserDefaults.standard.set(value, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
            }
        }
        return try await body()
    }

    /// The whole column, as the panel shows it: the search root parked beneath Library and a
    /// shelf's page on top.
    @Test func openingTheFilterPutsTheCaretInItNotTheParkedSearch() async throws {
        try await saved {
            let delegate = try #require(AppDelegate.shared, "the column takes the app's recents and ambience")
            let auth = AuthService()
            // The search field is there only signed in: the test host shares the app's cookies.
            await auth.refresh()
            try #require(auth.isSignedIn, "signed in to YouTube Music, as the app is")
            let music = YTMusicClient(auth: auth, persists: false, library: LibraryContent(albums: (1...3).map { BrowseItem(id: "MPREb-\($0)", kind: .album, title: "Album \($0)", subtitle: "Album • Tool") }), fetchAccount: { nil })
            let navigation = NavigationModel()
            navigation.isMiniPlayer = false
            navigation.path = []
            let view = RootView()
                .environment(auth)
                .environment(PlayerService(auth: auth, makeBridge: { FakeBridge() }))
                .environment(music)
                .environment(navigation)
                .environment(ScrollTracker())
                .environment(delegate.recents)
                .environment(CollapsedSections())
                .environment(delegate.ambience)
                .environment(NoticeCenter())
                .environment(PanelRest(schedule: { _, _ in {} }, isButtonDown: { false }))
                .frame(width: 320, height: 480)
            let panel = PanelWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 320, height: 480))
            panel.contentView = NSHostingView(rootView: view)
            panel.makeKeyAndOrderFront(nil)
            defer { panel.orderOut(nil); panel.close() }
            try await Task.sleep(for: .milliseconds(400))
            let content = panel.contentView!
            // Search used first, as it was live: its field had the caret before Library opened.
            let search = try #require(Self.field(prompt: "Search", in: content))
            let box = search.convert(search.bounds, to: nil)
            click(CGPoint(x: box.minX + 8, y: panel.frame.height - box.midY), in: panel)
            for _ in 0..<15 where !Self.isEditing(search, in: panel) { try await Task.sleep(for: .milliseconds(20)) }
            try #require(Self.isEditing(search, in: panel), "clicking Search puts the caret in it")
            navigation.path = [NavigationModel.library]
            try await Task.sleep(for: .milliseconds(500))
            navigation.path = [NavigationModel.library, LibraryShelf.albums.page]
            try await Task.sleep(for: .milliseconds(600))
            #expect(Self.field(prompt: "Filter Albums", in: content) == nil)
            // Live, opening the filter handed the caret to the parked search field, and the filter
            // took that field's editing for its own. The caret starts there, as it ended up live.
            panel.makeFirstResponder(search)
            try #require(Self.isEditing(search, in: panel))

            // ⌘F runs what the search button does.
            _ = panel.performKeyEquivalent(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber, context: nil, characters: "f", charactersIgnoringModifiers: "f", isARepeat: false, keyCode: 3)!)
            for _ in 0..<25 where Self.field(prompt: "Filter Albums", in: content) == nil { try await Task.sleep(for: .milliseconds(20)) }
            let filter = try #require(Self.field(prompt: "Filter Albums", in: content), "⌘F opens the filter")
            for _ in 0..<30 where !Self.isEditing(filter, in: panel) { try await Task.sleep(for: .milliseconds(20)) }
            let editing = (panel.firstResponder as? NSTextView)?.delegate as? NSTextField
            #expect(Self.isEditing(filter, in: panel), "the caret is in \(editing?.placeholderString ?? "nothing"), not the filter")
        }
    }

    /// The search root's field, alone in a key panel.
    private struct Field: View {
        @Bindable var navigation: NavigationModel
        var body: some View {
            SearchField(text: $navigation.query)
                .environment(navigation)
                .padding()
        }
    }

    @Test func clickingAnywhereInTheFieldPutsTheCaretInIt() async throws {
        try await saved {
            let navigation = NavigationModel()
            navigation.path = []
            let panel = PanelWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 320, height: 80))
            panel.contentView = NSHostingView(rootView: Field(navigation: navigation))
            panel.makeKeyAndOrderFront(nil)
            defer { panel.orderOut(nil); panel.close() }
            try await Task.sleep(for: .milliseconds(200))
            let content = panel.contentView!
            let field = try #require(Self.field(prompt: "Search", in: content))
            let text = field.convert(field.bounds, to: nil)
            // Top-left window coordinates: the magnifying glass left of the text, and the field's
            // padding just above it.
            let height = panel.frame.height
            let spots = [
                ("the placeholder", CGPoint(x: text.minX + 8, y: height - text.midY)),
                ("the magnifying glass", CGPoint(x: text.minX - Theme.Space.sm - 6, y: height - text.midY)),
                ("the padding above the text", CGPoint(x: text.midX, y: height - text.maxY - 4)),
                ("the padding right of the text", CGPoint(x: text.maxX + Theme.Space.md / 2, y: height - text.midY)),
            ]
            for (name, spot) in spots {
                panel.makeFirstResponder(nil)
                try await Task.sleep(for: .milliseconds(50))
                click(spot, in: panel)
                for _ in 0..<15 where !Self.isEditing(field, in: panel) { try await Task.sleep(for: .milliseconds(20)) }
                #expect(Self.isEditing(field, in: panel), "clicking \(name) left the caret out of the field")
            }

            // The clear button, right of the text once there is some, still clears it.
            navigation.query = "Tool"
            try await Task.sleep(for: .milliseconds(100))
            let typed = field.convert(field.bounds, to: nil)
            click(CGPoint(x: typed.maxX + Theme.Space.sm + 6, y: height - typed.midY), in: panel)
            for _ in 0..<15 where !navigation.query.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
            #expect(navigation.query.isEmpty, "the clear button left “\(navigation.query)”")
        }
    }

    // MARK: Helpers

    private func click(_ point: CGPoint, in window: NSWindow) {
        let location = CGPoint(x: point.x, y: window.frame.height - point.y)
        let time = ProcessInfo.processInfo.systemUptime
        for (type, offset) in [(NSEvent.EventType.leftMouseDown, 0.0), (.leftMouseUp, 0.05)] {
            window.sendEvent(NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: time + offset, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)!)
        }
    }

    private static func isEditing(_ field: NSTextField, in window: NSWindow) -> Bool {
        (window.firstResponder as? NSTextView)?.delegate === field
    }

    private static func field(prompt: String, in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.isEditable, field.placeholderString == prompt { return field }
        return view.subviews.lazy.compactMap { field(prompt: prompt, in: $0) }.first
    }
}
