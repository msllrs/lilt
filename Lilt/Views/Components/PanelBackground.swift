import AppKit
import SwiftUI

/// The panel's own surface, in the mode picked by `PanelStyle`: window-wide Liquid Glass, or the
/// sidebar material a Finder window uses. Both are window-server composited, so hiding is done
/// for real on the AppKit view rather than trusted to a SwiftUI fade (see `GlassBackground`).
struct PanelBackground: View {
    var cornerRadius: CGFloat = Theme.Radius.window
    var isHidden: Bool = false

    private var style: PanelStyle { ArtworkStyle.shared.panel }
    @Environment(NavigationModel.self) private var navigation

    var body: some View {
        // Behind-window surfaces aren't clipped by the native frame, so under it they follow the
        // window's live corner radius as it eases between the panel's and the platter's.
        #if NATIVE_FRAME
        let radius = navigation.frameCornerRadius
        #else
        let radius = cornerRadius
        #endif
        switch style.surface {
        case .glass:
            GlassBackground(cornerRadius: radius, isHidden: isHidden)
        case .sidebar:
            SidebarBackground(cornerRadius: radius, translucent: style.translucent, isHidden: isHidden)
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
        view.maskImage = cornerRadius > 0 ? Self.mask(cornerRadius: cornerRadius) : nil
        view.isHidden = isHidden
        Self.live.add(view)
        return view
    }

    /// Every mounted sidebar surface, so the native frame can re-mask them in the same display
    /// link tick that moves the window's corner; going through SwiftUI state lands a frame late,
    /// and for that frame rows show past the material's corner.
    nonisolated(unsafe) private static let live = NSHashTable<NSVisualEffectView>.weakObjects()

    @MainActor static func applyLiveCornerRadius(_ radius: CGFloat) {
        for view in live.allObjects { view.maskImage = radius > 0 ? mask(cornerRadius: radius) : nil }
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        // Inactive is the material's flat, opaque rendering: the look Reduce Transparency gives.
        view.state = translucent ? .active : .inactive
        if cornerRadius > 0, view.maskImage?.size.width != cornerRadius * 2 + 1 {
            view.maskImage = Self.mask(cornerRadius: cornerRadius)
        } else if cornerRadius == 0, view.maskImage != nil {
            view.maskImage = nil
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
