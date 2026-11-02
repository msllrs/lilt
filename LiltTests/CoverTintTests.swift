import AppKit
import SwiftUI
import Testing
@testable import Lilt

/// The platter's text and glyph colours were mixed in place until `CoverTint` took them over;
/// these pin the component to those formulas, written out again here, so the platter can't
/// drift while it's shared with other surfaces.
@MainActor
struct CoverTintTests {
    private static let accents: [Color] = [
        Color(red: 0.85, green: 0.1, blue: 0.1),
        Color(red: 0.1, green: 0.2, blue: 0.45),
        Color(red: 0.8, green: 0.8, blue: 0.0),
    ]

    private func resolved(_ color: Color, _ scheme: ColorScheme) -> Color.Resolved {
        var environment = EnvironmentValues()
        environment.colorScheme = scheme
        return color.resolve(in: environment)
    }

    private func expectSame(_ a: Color, _ b: Color, _ scheme: ColorScheme, _ role: String) {
        #expect(a == b, "\(role) in \(scheme) is no longer the platter's formula")
        #expect(resolved(a, scheme) == resolved(b, scheme), "\(role) in \(scheme) resolves differently")
    }

    @Test func matchesThePlattersOwnFormulas() {
        var platter = PlatterStyle.standard
        for (textTint, controlsTint) in [(platter.textTint, platter.controlsTint), (0.15, 0.9)] {
            platter.textTint = textTint
            platter.controlsTint = controlsTint
            for accent in Self.accents {
                for scheme in [ColorScheme.light, .dark] {
                    let tint = CoverTint(accent: accent, colorScheme: scheme, platter: platter)!
                    let mono = scheme == .dark ? Color.white : Color.black
                    expectSame(tint.title, mono.mix(with: accent, by: platter.textTint), scheme, "title")
                    expectSame(tint.secondary, Color.secondary.mix(with: accent, by: platter.textTint * 0.5), scheme, "artist")
                    expectSame(tint.tertiary, Color(nsColor: .tertiaryLabelColor).mix(with: accent, by: platter.textTint * 0.5), scheme, "times")
                    expectSame(tint.control, mono.mix(with: accent, by: platter.controlsTint), scheme, "controls")
                    expectSame(tint.dimControl, Color.secondary.mix(with: accent, by: platter.controlsTint), scheme, "dim controls")
                }
            }
        }
    }

    @Test func noAccentMeansNoTint() {
        #expect(CoverTint(accent: nil, colorScheme: .light, platter: .standard) == nil)
        #expect(CoverTint(accent: nil, colorScheme: .dark, textTint: 0.4, controlsTint: 0.64) == nil)
    }
}
