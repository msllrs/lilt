import AppKit
import SwiftUI

extension View {
    /// The edge treatment every list in the panel shares where it scrolls under a header or the
    /// platter. The headers draw their own blur (see `HeaderBackdrop`), so AppKit's scroll pocket
    /// is kept out of the way (see `ScrollPocketHider`).
    func panelScrollEdge() -> some View {
        scrollEdgeEffectStyle(.soft, for: .all)
            .background(ScrollPocketHider().allowsHitTesting(false))
    }
}

/// macOS 27 gives every hosted `NSScrollView` an `NSScrollPocket` under its top safe-area bar
/// (plus a pocket `BackdropView` beside it), which on browse pages draws the toolbar's
/// "ThinFilm" band and a hover hairline over the header's own blur. macOS 26 drew none here, and
/// no public API hides it (`scrollEdgeEffectHidden` and the titlebar separator don't reach it), so
/// this finds the list's scroll view and hides its pocket subviews, matched by class name so an
/// OS without the private class is left alone.
private struct ScrollPocketHider: NSViewRepresentable {
    func makeNSView(context: Context) -> HiderView { HiderView() }
    func updateNSView(_ view: HiderView, context: Context) { view.hidePockets() }

    final class HiderView: NSView {
        private weak var scrollView: NSScrollView?
        private var watched: [ObjectIdentifier: NSKeyValueObservation] = [:]
        private var frameObserver: NSObjectProtocol?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            hidePockets()
            // The scroll view is often built after this background, so look again next turn.
            if window != nil, scrollView == nil { DispatchQueue.main.async { [weak self] in self?.hidePockets() } }
        }

        override func layout() {
            super.layout()
            hidePockets()
        }

        /// Hides the pocket views of the scroll view this sits behind. Cheap enough to call on
        /// any layout: after the first lookup it only scans the scroll view's few direct subviews.
        func hidePockets() {
            guard window != nil else { return }
            if scrollView == nil { attach(to: scrollViewBeside()) }
            guard let scrollView else { return }
            for view in scrollView.subviews where Self.isPocket(view) {
                if !view.isHidden { view.isHidden = true }
                // If AppKit shows a pocket again (restyling it on hover, say), hide it right back.
                let id = ObjectIdentifier(view)
                if watched[id] == nil {
                    watched[id] = view.observe(\.isHidden) { view, _ in
                        MainActor.assumeIsolated { if !view.isHidden { view.isHidden = true } }
                    }
                }
            }
        }

        private static func isPocket(_ view: NSView) -> Bool {
            NSStringFromClass(type(of: view)).contains("NSScrollPocket")
        }

        private func attach(to found: NSScrollView?) {
            guard let found else { return }
            scrollView = found
            // AppKit lays pockets out again when the scroll view's size or safe area changes.
            found.postsFrameChangedNotifications = true
            frameObserver = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: found, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.hidePockets() }
            }
        }

        isolated deinit {
            if let frameObserver { NotificationCenter.default.removeObserver(frameObserver) }
        }
    }
}

extension NSView {
    /// The hosted scroll view a SwiftUI `.background` of a `ScrollView` belongs to. SwiftUI places
    /// a background beside the scroll view rather than inside it, so this searches a few levels
    /// around the view for the scroll view under its center.
    func scrollViewBeside() -> NSScrollView? {
        guard window != nil else { return nil }
        let center = convert(NSPoint(x: bounds.midX, y: bounds.midY), to: nil)
        func search(_ view: NSView, depth: Int) -> NSScrollView? {
            for sub in view.subviews where sub !== self {
                if let scroll = sub as? NSScrollView, !scroll.isHidden,
                   scroll.convert(scroll.bounds, to: nil).contains(center) { return scroll }
                if depth > 0, !(sub is NSScrollView), let found = search(sub, depth: depth - 1) { return found }
            }
            return nil
        }
        var ancestor = superview
        for _ in 0..<3 {
            guard let current = ancestor else { break }
            if let found = search(current, depth: 2) { return found }
            ancestor = current.superview
        }
        return nil
    }
}
