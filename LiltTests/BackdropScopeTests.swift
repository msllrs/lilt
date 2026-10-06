import AppKit
import Testing
@testable import Lilt

/// The header blur's "own content only" switch is a private flag on the backdrop layer, set as
/// the layer is built; a change of scope builds a new layer carrying the other value.
@MainActor
struct BackdropScopeTests {
    @Test func scopeFlagLandsOnTheLayer() throws {
        guard ProgressiveBlurBackdrop.isAvailable else { return }
        let view = BackdropHostView(frame: NSRect(x: 0, y: 0, width: 200, height: 60))
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        // Closing a window AppKit also releases, while Swift still holds it, frees it twice.
        window.isReleasedWhenClosed = false
        window.contentView = view
        func backdrop() throws -> CALayer { try #require(view.layer?.sublayers?.first?.sublayers?.first, "the backdrop layer sits in the clipped container") }
        #expect(try backdrop().value(forKey: "windowServerAware") as? Bool == false)
        let first = try backdrop()
        view.ownContentOnly = false
        #expect(try backdrop() !== first, "a change of scope builds a new layer")
        #expect(try backdrop().value(forKey: "windowServerAware") as? Bool == true)
        #expect(view.layer?.sublayers?.first?.sublayers?.count == 1, "the old layer is gone")
        view.ownContentOnly = true
        #expect(try backdrop().value(forKey: "windowServerAware") as? Bool == false)
        window.close()
    }
}
