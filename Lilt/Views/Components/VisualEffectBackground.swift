import AppKit
import SwiftUI

/// Window-wide Liquid Glass. The panel's content sits directly on glass, so inner surfaces use
/// plain fills rather than stacking more glass on top.
struct GlassBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSGlassEffectView {
        let view = NSGlassEffectView()
        view.style = .regular
        view.cornerRadius = 0
        return view
    }

    func updateNSView(_ view: NSGlassEffectView, context: Context) {}
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
