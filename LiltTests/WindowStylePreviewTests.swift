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
