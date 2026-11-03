import SwiftUI
import Testing
@testable import Lilt

/// The header controls (library, back, more, history, the search field) can be calmed like the
/// platter: a neutral tint fed into their glass and a faint backing behind it, both none by
/// default. A cover's cast, where a control has one, keeps the glass's tint.
@MainActor
struct HeaderControlCalmTests {
    @Test func noneByDefault() {
        let style = HeaderControlStyle.standard
        #expect(style.glassTint == 0 && style.backing == 0)
        #expect(HeaderControlStyle.glassTint(cast: nil, castOpacity: 0.24, neutral: .black, style: style) == nil)
    }

    @Test func theNeutralTintFillsInWhereThereIsNoCast() {
        var style = HeaderControlStyle.standard
        style.glassTint = 0.16
        #expect(HeaderControlStyle.glassTint(cast: nil, castOpacity: 0.24, neutral: .black, style: style) == Color.black.opacity(0.16))
        #expect(HeaderControlStyle.glassTint(cast: .red, castOpacity: 0.24, neutral: .black, style: style) == Color.red.opacity(0.24), "a cast keeps the tint")
    }

    @Test func copyValuesCarriesThem() {
        let style = ArtworkStyle()
        style.headerControls.glassTint = 0.16
        style.headerControls.backing = 0.08
        #expect(style.swiftSnippet.contains("reducedShadow: false, glassTint: 0.16, backing: 0.08)"))
    }
}
