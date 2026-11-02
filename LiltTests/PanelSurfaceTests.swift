import AppKit
import SwiftUI
import Testing
@testable import Lilt

/// `PanelBackground` mounts the surface the window style names, swaps it in place when the style
/// changes (leaving no stale surface behind), and keeps it on the window's live corner. Part of
/// `WindowStyleTests`, so nothing else edits the shared panel style while one of these runs.
extension WindowStyleTests {
    private func settle(_ frames: Int = 6) async {
        for _ in 0..<frames { try? await Task.sleep(for: .milliseconds(20)) }
    }

    private func surfaces(in view: NSView) -> (glass: [NSGlassEffectView], sidebar: [NSVisualEffectView]) {
        var glass: [NSGlassEffectView] = [], sidebar: [NSVisualEffectView] = []
        func walk(_ view: NSView) {
            if let view = view as? NSGlassEffectView { glass.append(view) }
            if let view = view as? NSVisualEffectView, view.material == .sidebar { sidebar.append(view) }
            view.subviews.forEach(walk)
        }
        walk(view)
        return (glass, sidebar)
    }

    @Test func switchingTheStyleSwapsTheMountedSurface() async throws {
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: WindowStyle.key)
        let panel = ArtworkStyle.shared.panel
        defer {
            ArtworkStyle.shared.panel = panel
            if let saved { defaults.set(saved, forKey: WindowStyle.key) } else { defaults.removeObject(forKey: WindowStyle.key) }
        }

        ArtworkStyle.shared.panel = WindowStyle.normal.panelStyle
        let navigation = NavigationModel()
        let size = CGSize(width: 320, height: 480)
        let hosting = NSHostingView(rootView: PanelBackground().environment(navigation).frame(width: size.width, height: size.height))
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -10_000, y: -10_000), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        // Closing a window AppKit also releases, while Swift still holds it, frees it twice.
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        defer { window.close() }
        func mounted() async -> (glass: [NSGlassEffectView], sidebar: [NSVisualEffectView]) {
            await settle()
            hosting.layoutSubtreeIfNeeded()
            return surfaces(in: hosting)
        }

        var now = await mounted()
        #expect(now.glass.isEmpty && now.sidebar.count == 1, "Normal is the sidebar material alone")
        #expect(now.sidebar.first?.state == .active)
        #expect(now.sidebar.first?.isHidden == false)

        ArtworkStyle.shared.panel = WindowStyle.glass.panelStyle
        now = await mounted()
        #expect(now.sidebar.isEmpty, "the sidebar surface is left behind")
        let glass = try #require(now.glass.first)
        #expect(now.glass.count == 1)
        #expect(glass.isHidden == false)
        #expect(glass.cornerRadius == navigation.frameCornerRadius)

        // The native frame re-corners the glass on its own tick, as it does the sidebar.
        GlassBackground.applyLiveCornerRadius(Theme.Radius.panel)
        #expect(glass.cornerRadius == Theme.Radius.panel)
        navigation.frameCornerRadius = Theme.Radius.panel
        now = await mounted()
        #expect(now.glass.first === glass, "a corner change keeps the same glass")
        #expect(glass.cornerRadius == Theme.Radius.panel)

        ArtworkStyle.shared.panel = WindowStyle.solid.panelStyle
        now = await mounted()
        #expect(now.glass.isEmpty, "the glass surface is left behind")
        let sidebar = try #require(now.sidebar.first)
        #expect(now.sidebar.count == 1)
        #expect(sidebar.state == .inactive, "Solid is the material's flat rendering")
        #expect(sidebar.maskImage?.size.width == Theme.Radius.panel * 2 + 1, "mounted on the window's current corner")

        ArtworkStyle.shared.panel = WindowStyle.normal.panelStyle
        now = await mounted()
        #expect(now.sidebar.first === sidebar, "translucency alone restyles the same view")
        #expect(sidebar.state == .active)
    }

    /// Reduce Transparency turns glass solid and leaves the sidebar styles as they are.
    @Test func reduceTransparencyTurnsGlassSolid() {
        #expect(WindowStyle.glass.panelStyle.effective(reduceTransparency: true) == WindowStyle.solid.panelStyle)
        #expect(WindowStyle.normal.panelStyle.effective(reduceTransparency: true) == WindowStyle.normal.panelStyle)
        #expect(WindowStyle.solid.panelStyle.effective(reduceTransparency: true) == WindowStyle.solid.panelStyle)
        for style in WindowStyle.allCases {
            #expect(style.panelStyle.effective(reduceTransparency: false) == style.panelStyle)
        }
    }
}
