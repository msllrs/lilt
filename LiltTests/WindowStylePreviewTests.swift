import AppKit
import SwiftUI
import Testing
@testable import Lilt

/// Settings ▸ Appearance draws each window style on its real surface, in miniature. Those
/// surfaces keep their own small corner: the native frame re-corners only the panel's own.
/// Part of `WindowStyleTests`, so nothing else edits the shared panel style while one runs.
extension WindowStyleTests {
    fileprivate func settle(_ frames: Int = 6) async {
        for _ in 0..<frames { try? await Task.sleep(for: .milliseconds(20)) }
    }

    /// Hosts `content` in an off-screen window; the caller closes it.
    fileprivate func mount(_ content: some View, size: CGSize) async -> (NSWindow, NSHostingView<AnyView>) {
        let hosting = NSHostingView(rootView: AnyView(content.frame(width: size.width, height: size.height)))
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -10_000, y: -10_000), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        // Closing a window AppKit also releases, while Swift still holds it, frees it twice.
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        hosting.layoutSubtreeIfNeeded()
        await settle(8)
        return (window, hosting)
    }

    fileprivate func subviews<T: NSView>(of type: T.Type, in view: NSView) -> [T] {
        var found: [T] = []
        func walk(_ view: NSView) {
            if let view = view as? T { found.append(view) }
            view.subviews.forEach(walk)
        }
        walk(view)
        return found
    }

    @Test func previewSurfacesKeepTheirOwnCorner() async throws {
        let small: CGFloat = 5
        let content = HStack {
            GlassBackground(cornerRadius: small, followsWindowCorner: false)
            SidebarBackground(cornerRadius: small, translucent: true, isHidden: false, followsWindowCorner: false)
            GlassBackground(cornerRadius: Theme.Radius.window)
        }
        let (window, hosting) = await mount(content, size: CGSize(width: 300, height: 100))
        defer { window.close() }

        let glass = subviews(of: NSGlassEffectView.self, in: hosting)
        let sidebar = subviews(of: NSVisualEffectView.self, in: hosting).filter { $0.material == .sidebar }
        #expect(glass.count == 2)
        let previewGlass = try #require(glass.first { $0.cornerRadius == small })
        let panelGlass = try #require(glass.first { $0.cornerRadius == Theme.Radius.window })
        let previewSidebar = try #require(sidebar.first)

        #expect(!GlassBackground.followsLiveCorner(previewGlass))
        #expect(!SidebarBackground.followsLiveCorner(previewSidebar))
        #expect(GlassBackground.followsLiveCorner(panelGlass), "the panel's own glass still follows")

        // The window easing into mini re-corners the panel's surfaces, and only those.
        GlassBackground.applyLiveCornerRadius(Theme.Radius.panel)
        SidebarBackground.applyLiveCornerRadius(Theme.Radius.panel)
        defer {
            GlassBackground.applyLiveCornerRadius(Theme.Radius.window)
            SidebarBackground.applyLiveCornerRadius(Theme.Radius.window)
        }
        #expect(previewGlass.cornerRadius == small)
        #expect(previewSidebar.maskImage?.size.width == small * 2 + 1)
        #expect(panelGlass.cornerRadius == Theme.Radius.panel)
    }
}

/// The cards themselves: each mounts the surface its style draws, and a click on one picks it.
extension WindowStyleTests {
    /// The picker as Settings wires it, straight onto the shared panel style.
    private struct WiredPicker: View {
        @Bindable var style = ArtworkStyle.shared
        var body: some View { WindowStylePicker(selection: $style.windowStyle) }
    }

    private static let pickerSize = CGSize(width: 320, height: 160)

    /// Runs `body` with the real stored choice and the shared panel style put back afterwards.
    private func preservingStyle(_ body: () async throws -> Void) async rethrows {
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: WindowStyle.key)
        let panel = ArtworkStyle.shared.panel
        defer {
            ArtworkStyle.shared.panel = panel
            if let saved { defaults.set(saved, forKey: WindowStyle.key) } else { defaults.removeObject(forKey: WindowStyle.key) }
        }
        try await body()
    }

    /// A single click at `point`, given in SwiftUI's coordinates (origin top-left).
    private func click(_ point: CGPoint, in window: NSWindow) async {
        let location = CGPoint(x: point.x, y: window.frame.height - point.y)
        let number = Int(Date.timeIntervalSinceReferenceDate * 1000) % 1_000_000
        let time = ProcessInfo.processInfo.systemUptime
        let down = NSEvent.mouseEvent(with: .leftMouseDown, location: location, modifierFlags: [], timestamp: time, windowNumber: window.windowNumber, context: nil, eventNumber: number, clickCount: 1, pressure: 1)!
        let up = NSEvent.mouseEvent(with: .leftMouseUp, location: location, modifierFlags: [], timestamp: time + 0.05, windowNumber: window.windowNumber, context: nil, eventNumber: number + 1, clickCount: 1, pressure: 0)!
        window.sendEvent(down)
        await settle(1)
        window.sendEvent(up)
        await settle(4)
    }

    @Test func eachCardMountsItsOwnSurface() async throws {
        try await preservingStyle {
            ArtworkStyle.shared.windowStyle = .normal
            let (window, hosting) = await mount(WiredPicker(), size: Self.pickerSize)
            defer { window.close() }

            let glass = subviews(of: NSGlassEffectView.self, in: hosting)
            let sidebar = subviews(of: NSVisualEffectView.self, in: hosting)
                .filter { $0.material == .sidebar }
                .sorted { $0.convert($0.bounds, to: nil).minX < $1.convert($1.bounds, to: nil).minX }
            // Reduce Transparency would show Glass as Solid; the cards then mount that instead.
            if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
                #expect(glass.isEmpty && sidebar.map(\.state) == [.inactive, .active, .inactive])
            } else {
                let card = try #require(glass.first)
                #expect(glass.count == 1, "Glass is window glass")
                #expect(sidebar.map(\.state) == [.active, .inactive], "Normal is the active material, Solid its flat rendering")
                #expect(card.cornerRadius == WindowStylePreview.cornerRadius)
                #expect(!GlassBackground.followsLiveCorner(card))
                #expect(card.convert(card.bounds, to: nil).minX < sidebar[0].convert(sidebar[0].bounds, to: nil).minX, "in Glass, Normal, Solid order")
            }
            for view in sidebar {
                #expect(!SidebarBackground.followsLiveCorner(view), "a preview stays off the live corner table")
                #expect(view.maskImage?.size.width == WindowStylePreview.cornerRadius * 2 + 1)
                #expect(view.frame.size == WindowStylePreview.size)
            }
        }
    }

    /// A click on a card's miniature, where the surface is, picks that style and saves it.
    @Test func clickingACardPicksItsStyle() async throws {
        try await preservingStyle {
            ArtworkStyle.shared.windowStyle = .glass
            let (window, _) = await mount(WiredPicker(), size: Self.pickerSize)
            defer { window.close() }
            let third = Self.pickerSize.width / 3

            // Cards share the width equally; aim at the middle of each one's miniature.
            await click(CGPoint(x: third * 2.5, y: Self.pickerSize.height / 2 - Theme.Space.md), in: window)
            #expect(ArtworkStyle.shared.panel == WindowStyle.solid.panelStyle)
            #expect(WindowStyle.stored() == .solid)

            await click(CGPoint(x: third * 1.5, y: Self.pickerSize.height / 2 - Theme.Space.md), in: window)
            #expect(ArtworkStyle.shared.windowStyle == .normal)
            #expect(WindowStyle.stored() == .normal)

            await click(CGPoint(x: third * 0.5, y: Self.pickerSize.height / 2 - Theme.Space.md), in: window)
            #expect(ArtworkStyle.shared.windowStyle == .glass)
            #expect(WindowStyle.stored() == .glass)
        }
    }
}
