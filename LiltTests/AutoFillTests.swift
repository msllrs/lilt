import AppKit
import Testing
@testable import Lilt

/// An empty frosted box showed under the search field as Lilt opened: macOS's AutoFill
/// heuristics (since macOS 26) reacting to the field taking focus as the panel becomes key,
/// drawn by the "AutoFill (Lilt)" helper before it found nothing to offer. Turned off for a
/// launch with the defaults key below, the box didn't appear. Lilt has nothing for AutoFill to
/// fill (a search field and a filter), so the app registers the key off itself, as Chromium,
/// Electron and Zed do. A value set with `defaults write` still wins over a registered one.
struct AutoFillTests {
    @Test func liltTurnsAutoFillHeuristicsOffAtLaunch() {
        let registered = UserDefaults.standard.volatileDomain(forName: UserDefaults.registrationDomain)
        #expect(registered["NSAutoFillHeuristicControllerEnabled"] as? Bool == false,
                "registered off by the app, not only by a defaults write on this Mac")
    }
}
