import SwiftUI
import Testing
@testable import Lilt

/// The platter's glass can be today's regular glass or the search field's clear glass, with the
/// cover's colour laid over it as today either way. `PlatterStyle.layers` says what is drawn.
@MainActor
struct PlatterGlassTests {
    /// Today's surface values for the strengths the layers scale.
    private let tint = 0.48, hover = 0.24

    @Test func theStandardPlatterIsTodays() {
        let style = PlatterStyle.standard
        #expect(style.glass == .current)
        #expect(style.colorStrength == 1)
        let layers = style.layers(tintOpacity: tint, hoverBrightness: hover, hovering: false, reduceTransparency: false)
        #expect(layers.material == .regular)
        #expect(layers.coverOpacity == tint)
        #expect(layers.washOpacity == 1)
        // Hover brightens the cover wash just as before.
        #expect(style.layers(tintOpacity: tint, hoverBrightness: hover, hovering: true, reduceTransparency: false).coverOpacity == tint * (1 + hover))
    }

    /// Clear is the search field's glass under the same colour: only the material changes.
    @Test func clearKeepsTodaysColour() {
        var style = PlatterStyle.standard
        style.glass = .clear
        let today = PlatterStyle.standard.layers(tintOpacity: tint, hoverBrightness: hover, hovering: true, reduceTransparency: false)
        let clear = style.layers(tintOpacity: tint, hoverBrightness: hover, hovering: true, reduceTransparency: false)
        #expect(clear.material == .clear)
        #expect(clear.coverOpacity == today.coverOpacity)
        #expect(clear.washOpacity == today.washOpacity)
    }

    /// The strength dial thins the cover and the wash together, letting the glass show.
    @Test func colorStrengthScalesTheColourLayers() {
        var style = PlatterStyle.standard
        style.glass = .clear
        style.colorStrength = 0.48
        let layers = style.layers(tintOpacity: tint, hoverBrightness: hover, hovering: false, reduceTransparency: false)
        #expect(abs(layers.coverOpacity - tint * 0.48) < 1e-9)
        #expect(layers.washOpacity == 0.48)
    }

    /// Reduce Transparency keeps the regular glass: clear's whole point is seeing through.
    @Test func reduceTransparencyFallsBackToRegular() {
        var style = PlatterStyle.standard
        style.glass = .clear
        #expect(style.layers(tintOpacity: tint, hoverBrightness: hover, hovering: false, reduceTransparency: true).material == .regular)
    }

    @Test func copyValuesCarriesTheGlass() {
        let style = ArtworkStyle()
        #expect(style.swiftSnippet.contains("alwaysGlass: true, glass: .current, colorStrength: 1.00)"))
        style.platter.glass = .clear
        style.platter.colorStrength = 0.64
        #expect(style.swiftSnippet.contains("alwaysGlass: true, glass: .clear, colorStrength: 0.64)"))
    }
}
