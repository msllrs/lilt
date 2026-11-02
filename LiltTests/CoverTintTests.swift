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

/// Album pages wear their cover's colour; nothing else does, and the guard keeps it readable.
@MainActor
struct PageCoverTintTests {
    /// Solid covers through the real cache, so the accents are what a page would get: from the
    /// very dark and very light, which have no colour to speak of, to saturated ones.
    static func accent(_ name: String, _ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> Color? {
        let url = URL(string: "https://lh3.googleusercontent.com/test-cover-tint-\(name)=w120-h120-l90-rj")!
        if ImageCache.shared.cached(url) == nil {
            let image = NSImage(size: NSSize(width: 120, height: 120), flipped: false) { rect in
                NSColor(srgbRed: r, green: g, blue: b, alpha: 1).setFill()
                rect.fill()
                return true
            }
            ImageCache.shared.store(image, for: url)
        }
        return ImageCache.shared.accent(for: url, saturationBoost: ArtworkStyle.shared.platter.scrubberSaturation)
    }

    static let saturated: [(String, CGFloat, CGFloat, CGFloat)] = [
        ("navy", 0.04, 0.06, 0.30), ("blue", 0.1, 0.2, 0.95), ("purple", 0.45, 0.1, 0.8),
        ("red", 0.9, 0.1, 0.1), ("yellow", 1.0, 0.95, 0.1), ("lime", 0.5, 1.0, 0.1),
        ("cyan", 0.1, 0.9, 1.0), ("pink", 1.0, 0.5, 0.8),
    ]

    @Test func onlyAlbumsWearTheirCover() {
        let accent = Color(red: 0.8, green: 0.2, blue: 0.2)
        #expect(BrowseScreen.wearsCoverTint(.album))
        for kind in [BrowseKind.playlist, .artist, .library] {
            #expect(!BrowseScreen.wearsCoverTint(kind))
            #expect(BrowseScreen.coverTint(kind: kind, accent: accent, colorScheme: .light) == nil)
            #expect(BrowseScreen.coverTint(kind: kind, accent: accent, colorScheme: .dark) == nil)
        }
        #expect(BrowseScreen.coverTint(kind: .album, accent: accent, colorScheme: .light) != nil)
        #expect(BrowseScreen.coverTint(kind: .album, accent: nil, colorScheme: .light) == nil)
    }

    /// By default a page takes the platter's shares; the page's own dials apply once it stops
    /// following, and the guard can be turned off to see the raw mix.
    @Test func pageSharesFollowThePlatterUntilToldOtherwise() throws {
        let accent = Color(red: 0.8, green: 0.2, blue: 0.2)
        var style = PageTintStyle.standard
        style.contrastGuard = false
        let platter = ArtworkStyle.shared.platter
        let following = try #require(BrowseScreen.coverTint(kind: .album, accent: accent, colorScheme: .light, style: style))
        #expect(following.titleMix == platter.textTint && following.controlMix == platter.controlsTint)
        style.followsPlatter = false
        style.textTint = 0.25
        style.controlsTint = 0.5
        let own = try #require(BrowseScreen.coverTint(kind: .album, accent: accent, colorScheme: .dark, style: style))
        #expect(own.titleMix == 0.25 && own.secondaryMix == 0.125 && own.controlMix == 0.5)
        #expect(own.highlightOpacity == style.darkHighlightOpacity)
    }

    @Test func theEnvironmentStartsUntinted() {
        #expect(EnvironmentValues().coverTint == nil)
    }

    /// Black and white covers have no accent, so their pages keep the plain label colours.
    @Test func greyCoversAreLeftPlain() {
        #expect(Self.accent("black", 0.02, 0.02, 0.02) == nil)
        #expect(Self.accent("white", 0.98, 0.98, 0.98) == nil)
    }

    @Test func tintedTextStaysReadable() throws {
        for (name, r, g, b) in Self.saturated {
            let accent = try #require(Self.accent(name, r, g, b), "\(name) should have an accent")
            for scheme in [ColorScheme.light, .dark] {
                let tint = try #require(BrowseScreen.coverTint(kind: .album, accent: accent, colorScheme: scheme))
                let mono: Color = scheme == .dark ? .white : .black
                let roles: [(String, Color, Color, Double)] = [
                    ("title", tint.title, mono, CoverTint.titleFloor),
                    ("secondary", tint.secondary, .secondary, CoverTint.secondaryFloor),
                    ("tertiary", tint.tertiary, Color(nsColor: .tertiaryLabelColor), CoverTint.tertiaryFloor),
                    ("control", tint.control, mono, CoverTint.titleFloor),
                    ("dim control", tint.dimControl, .secondary, CoverTint.secondaryFloor),
                ]
                for (role, tinted, plain, minimum) in roles {
                    let floor = min(tint.contrast(plain), minimum)
                    let got = tint.contrast(tinted)
                    #expect(got >= floor - 0.01, "\(name) \(role) in \(scheme): \(got) under \(floor)")
                }
            }
        }
    }
}
