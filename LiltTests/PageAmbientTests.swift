import SwiftUI
import Testing
@testable import Lilt

/// The cover's light at the top of a page, once the page scrolls on past the album's tracks to
/// the related sections: whether it stays pinned or leaves with the hero, how far it dims as the
/// first related section reaches the top, and whether those sections' headers wear the cover.
@MainActor
struct PageAmbientTests {
    /// Until the tweak panel says otherwise, the page looks as it always has: pinned to the top,
    /// at full strength however far it scrolls, with the related headers tinted.
    @Test func theStandardStyleIsTodaysLook() {
        let style = PageAmbientStyle.standard
        #expect(style.band == 0.5 && style.reach == 360)
        #expect(style.scroll == .pinned)
        #expect(style.sectionFade == 0)
        #expect(style.tintsSectionHeaders)
        for offset: CGFloat in [-40, 0, 200, 600, 2_000] {
            #expect(style.offset(scrollOffset: offset) == 0)
            for start: CGFloat? in [nil, 0, 400, 800] {
                #expect(style.opacity(scrollOffset: offset, sectionsStart: start) == 1)
            }
        }
    }

    /// `reset()` puts back `.standard` whole, so the new dials are covered; a style built with
    /// the new fields set is not the standard one. (reset() itself also stores the window
    /// style, so it isn't called here, in the app's own defaults.)
    @Test func theNewDialsAreSeparateFromStandard() {
        #expect(PageAmbientStyle() == .standard)
        #expect(PageAmbientStyle(scroll: .scrolls) != .standard)
        #expect(PageAmbientStyle(sectionFade: 1) != .standard)
        #expect(PageAmbientStyle(sectionFadeDistance: 50) != .standard)
        #expect(PageAmbientStyle(tintsSectionHeaders: false) != .standard)
    }

    /// Pinned stays at the panel top; scrolling moves it up with the content, but a pull past
    /// the top doesn't drag it down off the panel's edge.
    @Test func scrollingModeMovesWithTheContent() {
        var style = PageAmbientStyle.standard
        style.scroll = .scrolls
        #expect(style.offset(scrollOffset: 0) == 0)
        #expect(style.offset(scrollOffset: 120) == -120)
        #expect(style.offset(scrollOffset: -30) == 0)
    }

    /// The wash dims over the fade distance, reaching its full dimming as the first related
    /// section reaches the top of the panel, and stays there beyond it.
    @Test func fadesAsTheFirstSectionReachesTheTop() {
        var style = PageAmbientStyle.standard
        style.sectionFade = 0.8
        style.sectionFadeDistance = 200
        let start: CGFloat = 1_000
        // Further than the fade distance away: untouched.
        #expect(style.opacity(scrollOffset: 0, sectionsStart: start) == 1)
        #expect(style.opacity(scrollOffset: 800, sectionsStart: start) == 1)
        // Halfway through the distance: half the dimming.
        #expect(abs(style.opacity(scrollOffset: 900, sectionsStart: start) - 0.6) < 1e-9)
        // At the top and past it: the full dimming.
        #expect(abs(style.opacity(scrollOffset: 1_000, sectionsStart: start) - 0.2) < 1e-9)
        #expect(abs(style.opacity(scrollOffset: 1_500, sectionsStart: start) - 0.2) < 1e-9)
        // A page with no sections after its tracks never fades.
        #expect(style.opacity(scrollOffset: 1_500, sectionsStart: nil) == 1)
    }

    /// A fade of 1 takes the wash away entirely; a zero distance is a cut at the top.
    @Test func fullFadeAndZeroDistance() {
        var style = PageAmbientStyle.standard
        style.sectionFade = 1
        style.sectionFadeDistance = 0
        #expect(style.opacity(scrollOffset: 499, sectionsStart: 500) == 1)
        #expect(style.opacity(scrollOffset: 500, sectionsStart: 500) == 0)
    }

    /// "Copy values" carries the new dials.
    @Test func copyValuesCarriesTheNewDials() {
        let style = ArtworkStyle()
        #expect(style.swiftSnippet.contains("pageAmbient = PageAmbientStyle(band: 0.50, reach: 360.00, scroll: .pinned, sectionFade: 0.00, sectionFadeDistance: 200.00, tintsSectionHeaders: true)"))
        style.pageAmbient.scroll = .scrolls
        style.pageAmbient.sectionFade = 0.65
        style.pageAmbient.sectionFadeDistance = 120
        style.pageAmbient.tintsSectionHeaders = false
        #expect(style.swiftSnippet.contains("pageAmbient = PageAmbientStyle(band: 0.50, reach: 360.00, scroll: .scrolls, sectionFade: 0.65, sectionFadeDistance: 120.00, tintsSectionHeaders: false)"))
    }
}
