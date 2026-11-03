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

    /// Frost lays the regular glass over the clear at its strength, from 0 (all clear, as Clear
    /// has been) to 1 (all frosted, today's glass); the colour above is untouched. The regular
    /// glass needs none, and Reduce Transparency is regular already.
    @Test func frostBlendsClearTowardsRegular() {
        var style = PlatterStyle.standard
        #expect(style.frost == 0)
        style.glass = .clear
        #expect(style.layers(tintOpacity: tint, hoverBrightness: hover, hovering: false, reduceTransparency: false).frost == 0)
        style.frost = 0.32
        let frosted = style.layers(tintOpacity: tint, hoverBrightness: hover, hovering: false, reduceTransparency: false)
        #expect(frosted.material == .clear && frosted.frost == 0.32)
        #expect(frosted.coverOpacity == tint && frosted.washOpacity == 1)
        #expect(style.layers(tintOpacity: tint, hoverBrightness: hover, hovering: false, reduceTransparency: true).frost == 0)
        style.glass = .current
        #expect(style.layers(tintOpacity: tint, hoverBrightness: hover, hovering: false, reduceTransparency: false).frost == 0)
    }

    /// Glass tint (a neutral colour fed into the glass itself) and backing (a faint fill behind
    /// it) calm what shows through, on either glass; both start at none, so nothing changes.
    @Test func glassTintAndBackingPassThrough() {
        var style = PlatterStyle.standard
        #expect(style.glassTint == 0 && style.backing == 0)
        let none = style.layers(tintOpacity: tint, hoverBrightness: hover, hovering: false, reduceTransparency: false)
        #expect(none.glassTint == 0 && none.backing == 0)
        for glass in PlatterGlass.allCases {
            style.glass = glass
            style.glassTint = 0.16
            style.backing = 0.24
            let layers = style.layers(tintOpacity: tint, hoverBrightness: hover, hovering: false, reduceTransparency: false)
            #expect(layers.glassTint == 0.16 && layers.backing == 0.24)
            #expect(layers.coverOpacity == tint && layers.washOpacity == 1, "the colour above is untouched")
        }
    }

    /// Reduce Transparency keeps the regular glass: clear's whole point is seeing through.
    @Test func reduceTransparencyFallsBackToRegular() {
        var style = PlatterStyle.standard
        style.glass = .clear
        #expect(style.layers(tintOpacity: tint, hoverBrightness: hover, hovering: false, reduceTransparency: true).material == .regular)
    }

    @Test func copyValuesCarriesTheGlass() {
        let style = ArtworkStyle()
        #expect(style.swiftSnippet.contains("alwaysGlass: true, glass: .current, colorStrength: 1.00, frost: 0.00, glassTint: 0.00, backing: 0.00)"))
        style.platter.glass = .clear
        style.platter.colorStrength = 0.64
        style.platter.frost = 0.32
        style.platter.glassTint = 0.16
        style.platter.backing = 0.08
        #expect(style.swiftSnippet.contains("alwaysGlass: true, glass: .clear, colorStrength: 0.64, frost: 0.32, glassTint: 0.16, backing: 0.08)"))
    }
}
