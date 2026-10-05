import AppKit
import SwiftUI
import Testing
@testable import Lilt

/// The AppKit header-control surface drives `NSGlassEffectView`'s private dials through KVC.
/// Every value the tweak panel can produce must land without raising: a wrong value type throws
/// an Objective-C exception, which takes the whole app down.
@MainActor
struct GlassSurfaceTests {
    @Test func everyTweakPanelValueAppliesWithoutRaising() {
        let view = NSGlassEffectView()
        var style = HeaderControlStyle.standard
        style.mode = .appKit

        // The ranges are the ones TweakPanel's controls offer.
        for subvariant in ["", "default", "regular", "clear"] {
            style.subvariant = subvariant
            GlassSurface<Circle>.apply(style, to: view)
        }
        for variant in HeaderControlStyle.variantRange {
            style.variant = variant
            GlassSurface<Circle>.apply(style, to: view)
        }
        for value in HeaderControlStyle.scrimRange { style.scrim = value; GlassSurface<Circle>.apply(style, to: view) }
        for value in HeaderControlStyle.subduedRange { style.subdued = value; GlassSurface<Circle>.apply(style, to: view) }
        for value in HeaderControlStyle.interactionRange { style.interaction = value; GlassSurface<Circle>.apply(style, to: view) }
        for value in HeaderControlStyle.adaptiveAppearanceRange { style.adaptiveAppearance = value; GlassSurface<Circle>.apply(style, to: view) }
        for flag in [true, false] {
            style.clearBase = flag
            style.contentLensing = flag
            style.reducedShadow = flag
            GlassSurface<Circle>.apply(style, to: view)
        }
        #expect(view.style == .regular)
        #expect(view.value(forKey: "_subvariant") as? String == "clear")
        #expect(view.value(forKey: "_variant") as? Int == HeaderControlStyle.variantRange.upperBound)
    }

    /// The enum-backed dials trap on values past their last case; out-of-range input is clamped.
    @Test func enumDialsAreClampedToWhatAppKitAccepts() {
        let view = NSGlassEffectView()
        var style = HeaderControlStyle.standard
        style.mode = .appKit
        style.interaction = 9
        style.adaptiveAppearance = -4
        GlassSurface<Circle>.apply(style, to: view)
        #expect(view.value(forKey: "_interactionState") as? Int == HeaderControlStyle.interactionRange.upperBound)
        #expect(view.value(forKey: "_adaptiveAppearance") as? Int == HeaderControlStyle.adaptiveAppearanceRange.lowerBound)
    }

    /// The private setters' argument types match what `apply` sends. If AppKit changes a dial's
    /// type, this says which one; `apply` will already be skipping that write instead of raising.
    @Test func privateSettersTakeTheTypesWeSend() {
        let view = NSGlassEffectView()
        for (key, code) in GlassSurface<Circle>.privateKeys {
            #expect(GlassSurface<Circle>.setter(for: key, on: view) == code, "\(key)")
        }
    }

    /// A value of the wrong type is skipped, not sent.
    @Test func mismatchedValuesAreRefused() {
        typealias Glass = GlassSurface<Circle>
        #expect(Glass.accepts("@", nil))
        #expect(Glass.accepts("@", "default"))
        #expect(!Glass.accepts("@", 1))
        #expect(Glass.accepts("q", 1))
        #expect(!Glass.accepts("q", "1"))
        #expect(!Glass.accepts("q", nil))
        #expect(Glass.accepts("B", true))
        #expect(!Glass.accepts("B", 1))
        #expect(Glass.setter(for: "_noSuchDial", on: NSGlassEffectView()) == nil)
    }
}
