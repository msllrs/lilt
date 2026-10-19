import AppKit
import SwiftUI

extension View {
    /// Pulling the list down past its top runs `action`, with AppKit's refresh indicator showing
    /// until it returns. Apply it to the `ScrollView` itself. macOS 27 only: SwiftUI's
    /// `.refreshable` installs nothing on the Mac, and `NSRefreshController` is new there; on
    /// earlier systems the list is left as it was. `isEnabled` is fixed for a screen's lifetime
    /// (a page's kind), so switching branches never rebuilds a live list.
    @ViewBuilder
    func pullToRefresh(isEnabled: Bool = true, _ action: @escaping @MainActor () async -> Void) -> some View {
        if isEnabled, #available(macOS 27, *) {
            background(RefreshControllerAttacher(action: action).allowsHitTesting(false))
        } else {
            self
        }
    }
}

/// Gives the hosted scroll view this sits beside an `NSRefreshController` whose action runs the
/// SwiftUI side's refresh.
@available(macOS 27, *)
private struct RefreshControllerAttacher: NSViewRepresentable {
    let action: @MainActor () async -> Void

    func makeNSView(context: Context) -> AttacherView { AttacherView() }
    func updateNSView(_ view: AttacherView, context: Context) {
        view.action = action
        view.attach()
    }

    final class AttacherView: NSView {
        var action: (@MainActor () async -> Void)?
        private weak var scrollView: NSScrollView?
        private let controller = NSRefreshController()

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            attach()
            // The scroll view is often built after this background, so look again next turn.
            if window != nil, scrollView == nil { DispatchQueue.main.async { [weak self] in self?.attach() } }
        }

        override func layout() {
            super.layout()
            attach()
        }

        /// Installs the controller once the scroll view is found; cheap to call again after.
        func attach() {
            guard scrollView == nil, let found = scrollViewBeside() else { return }
            scrollView = found
            controller.target = self
            controller.action = #selector(refresh(_:))
            found.refreshController = controller
        }

        @objc private func refresh(_ sender: Any?) {
            guard let action else { controller.endRefreshing(); return }
            Task { [weak self] in
                await action()
                self?.controller.endRefreshing()
            }
        }

        isolated deinit {
            if scrollView?.refreshController === controller { scrollView?.refreshController = nil }
        }
    }
}
