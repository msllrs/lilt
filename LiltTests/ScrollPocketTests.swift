import AppKit
import SwiftUI
import Testing
@testable import Lilt

/// macOS 27 draws an AppKit scroll pocket under a scroll view's top safe-area bar. macOS 26 drew
/// none in the panel, so the headers draw their own blur (`HeaderBackdrop`); on 27 the pocket
/// came out on browse pages as the "ThinFilm" band window toolbars use, with a hairline on
/// hover. Lists in the panel keep the system's pocket out of the way.
@MainActor
struct ScrollPocketTests {
    /// The header bar's height, changeable so the test can move the scroll view's safe area.
    @Observable final class Bar { var height: CGFloat = 52 }

    /// A list under a header bar, the way the panel's screens lay one out.

    private struct Page: View {
        let bar: Bar
        var body: some View {
            ScrollView {
                LazyVStack(spacing: 0) { ForEach(0..<40) { Text("Row \($0)").frame(height: 52) } }
            }
            .panelScrollEdge()
            .safeAreaBar(edge: .top, spacing: 0) { Color.clear.frame(height: bar.height) }
        }
    }

    @Test func listsDrawNoSystemScrollPocket() {
        let bar = Bar()
        let panel = PanelWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 320, height: 600))
        panel.contentView = NSHostingView(rootView: Page(bar: bar))
        panel.orderFront(nil)
        defer { panel.orderOut(nil); panel.close() }
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
        // Pockets are built and styled after the first layout pass.
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))

        func walk(_ layer: CALayer, visible: Bool, inPocket: Bool) {
            let visible = visible && !layer.isHidden && layer.opacity > 0
            let inPocket = inPocket || layer.name == "NSScrollPocket" || (layer.name?.contains("NSScrollPocket") ?? false)
            if visible, inPocket, !layer.bounds.isEmpty { drawn.append(layer.name ?? "\(type(of: layer))") }
            layer.sublayers?.forEach { walk($0, visible: visible, inPocket: inPocket) }
        }
        var drawn: [String] = []
        func check(_ moment: String) {
            drawn = []
            if let root = panel.contentView?.superview?.layer { walk(root, visible: true, inPocket: false) }
            #expect(drawn.isEmpty, "visible scroll-pocket layers \(moment): \(drawn)")
        }
        func settle() {
            panel.contentView?.layoutSubtreeIfNeeded()
            panel.displayIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        }
        check("at rest")

        // AppKit restyles the pocket as content passes under the bar and rebuilds it when the
        // scroll view's size or safe area changes; it has to stay out of the way through both.
        let scrollView = findScrollView(in: panel.contentView)
        #expect(scrollView != nil)
        if let clip = scrollView?.contentView {
            clip.scroll(to: NSPoint(x: 0, y: 300))
            scrollView?.reflectScrolledClipView(clip)
            settle()
            check("after scrolling")
        }
        panel.setFrame(NSRect(x: -10_000, y: -10_000, width: 360, height: 480), display: true)
        settle()
        check("after resizing")
        bar.height = 88
        settle()
        check("after the bar changed height")

        // AppKit's own restyling (hover brings in the hairline) may show a pocket again.
        for view in scrollView?.subviews ?? [] where NSStringFromClass(type(of: view)).contains("NSScrollPocket") {
            view.isHidden = false
        }
        settle()
        check("after AppKit showed the pocket again")
    }

    private func findScrollView(in view: NSView?) -> NSScrollView? {
        guard let view else { return nil }
        if let scroll = view as? NSScrollView { return scroll }
        for sub in view.subviews { if let found = findScrollView(in: sub) { return found } }
        return nil
    }
}
