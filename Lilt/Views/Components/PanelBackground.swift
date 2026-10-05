import AppKit
import SwiftUI

/// The panel's own surface, in the mode picked by `PanelStyle`: window-wide Liquid Glass, or the
/// sidebar material a Finder window uses. Both are window-server composited, so hiding is done
/// for real on the AppKit view rather than trusted to a SwiftUI fade (see `GlassBackground`).
struct PanelBackground: View {
    var cornerRadius: CGFloat = Theme.Radius.window
    var isHidden: Bool = false

    private var style: PanelStyle { ArtworkStyle.shared.panel }

    var body: some View {
        switch style.surface {
        case .glass:
            GlassBackground(cornerRadius: cornerRadius, isHidden: isHidden)
        case .sidebar:
            SidebarBackground(cornerRadius: cornerRadius, translucent: style.translucent, isHidden: isHidden)
        }
    }
}

/// The one line a window frame gives a sidebar: dark on a light desktop, light on a dark one.
/// Drawn above the content (see RootView), not under it, so the header blur can't erase it and
/// it covers the seam where rows pass the material's edge. Nothing for the glass surface, which
/// has a rim of its own.
struct PanelEdge: View {
    var cornerRadius: CGFloat = Theme.Radius.window

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if ArtworkStyle.shared.panel.surface == .sidebar {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.12), lineWidth: 1)
                .allowsHitTesting(false)
        }
    }
}

/// `NSVisualEffectView` with the sidebar material, blended behind the window and kept active so
/// it stays as vibrant as a Finder window's sidebar while Lilt isn't the key app. The shape comes
/// from `maskImage`: a layer mask wouldn't limit the behind-window blur region.
struct SidebarBackground: NSViewRepresentable {
    var cornerRadius: CGFloat
    var translucent: Bool
    var isHidden: Bool

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.maskImage = Self.mask(cornerRadius: cornerRadius)
        view.isHidden = isHidden
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        // Inactive is the material's flat, opaque rendering: the look Reduce Transparency gives.
        view.state = translucent ? .active : .inactive
        if view.maskImage?.size.width != cornerRadius * 2 + 1 {
            view.maskImage = Self.mask(cornerRadius: cornerRadius)
        }
        if isHidden {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak view] in
                if let view, context.coordinator.wantsHidden { view.isHidden = true }
            }
        } else {
            view.isHidden = false
        }
        context.coordinator.wantsHidden = isHidden
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator { var wantsHidden = false }

    /// A stretchable rounded rectangle with the same continuous corners as the rest of the shell.
    static func mask(cornerRadius radius: CGFloat) -> NSImage {
        let side = radius * 2 + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let path = RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect).cgPath
            context.addPath(path)
            context.setFillColor(NSColor.black.cgColor)
            context.fillPath()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
