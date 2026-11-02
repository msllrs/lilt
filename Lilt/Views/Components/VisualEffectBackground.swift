import AppKit
import SwiftUI

/// Window-wide Liquid Glass. The panel's content sits directly on glass, so inner surfaces use
/// plain fills rather than stacking more glass on top.
struct GlassBackground: NSViewRepresentable {
    var cornerRadius: CGFloat = Theme.Radius.window
    /// The glass is composited by the window server, so a SwiftUI fade or removal doesn't
    /// reliably switch it off. When `isHidden`, the view is hidden for real once the fade has
    /// had time to finish.
    var isHidden: Bool = false
    /// The panel's own glass follows the window's live corner (see `live`). A preview of it
    /// elsewhere (Settings ▸ Appearance) keeps the radius it was given.
    var followsWindowCorner: Bool = true

    func makeNSView(context: Context) -> NSGlassEffectView {
        let view = NSGlassEffectView()
        view.style = .regular
        view.cornerRadius = cornerRadius
        view.isHidden = isHidden
        if followsWindowCorner { Self.live.add(view) }
        return view
    }

    /// Every mounted glass surface that follows the window's corner, re-cornered by the native frame in the same display link tick
    /// that moves the window's corner, as `SidebarBackground` is; through SwiftUI state the glass
    /// would trail the window's corner by a frame on the way into and out of mini.
    nonisolated(unsafe) private static let live = NSHashTable<NSGlassEffectView>.weakObjects()

    @MainActor static func applyLiveCornerRadius(_ radius: CGFloat) {
        for view in live.allObjects { view.cornerRadius = radius }
    }

    /// Whether the native frame re-corners `view` as the window's corner moves.
    @MainActor static func followsLiveCorner(_ view: NSGlassEffectView) -> Bool { live.contains(view) }

    func updateNSView(_ view: NSGlassEffectView, context: Context) {
        view.cornerRadius = cornerRadius
        if isHidden {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak view] in
                // Still meant to be hidden? (A quick toggle back shouldn't blink it off.)
                if let view, context.coordinator.wantsHidden { view.isHidden = true }
            }
        } else {
            view.isHidden = false
        }
        context.coordinator.wantsHidden = isHidden
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator { var wantsHidden = false }
}

/// Classic translucent material, kept `.active` so it stays vibrant while another app has focus.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}
