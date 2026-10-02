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

    func makeNSView(context: Context) -> NSGlassEffectView {
        let view = NSGlassEffectView()
        view.style = .regular
        view.cornerRadius = cornerRadius
        view.isHidden = isHidden
        return view
    }

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
