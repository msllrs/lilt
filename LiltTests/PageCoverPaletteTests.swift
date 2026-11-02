import AppKit
import SwiftUI
import Testing
@testable import Lilt

/// Album pages wear their cover's palette; nothing else does, and the guard keeps it readable.
@MainActor
struct PageCoverPaletteTests {
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
        return ImageCache.shared.accent(for: url, saturationBoost: CoverPaletteStyle.standard.accentSaturation)
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
            for scheme in [ColorScheme.light, .dark] {
                let palette = BrowseScreen.palette(kind: kind, accent: accent, colorScheme: scheme)
                #expect(palette.primary == nil && palette.control == nil && palette.highlight == nil)
            }
        }
        #expect(BrowseScreen.palette(kind: .album, accent: accent, colorScheme: .light).primary != nil)
        #expect(BrowseScreen.palette(kind: .album, accent: nil, colorScheme: .light).primary == nil)
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
                let palette = BrowseScreen.palette(kind: .album, accent: accent, colorScheme: scheme)
                let mono: Color = scheme == .dark ? .white : .black
                let roles: [(String, Color?, Color, Double)] = [
                    ("primary", palette.primary, mono, CoverPalette.primaryFloor),
                    ("secondary", palette.secondary, .secondary, CoverPalette.secondaryFloor),
                    ("tertiary", palette.tertiary, Color(nsColor: .tertiaryLabelColor), CoverPalette.tertiaryFloor),
                    ("control", palette.control, mono, CoverPalette.primaryFloor),
                    ("dim control", palette.dimControl, .secondary, CoverPalette.secondaryFloor),
                ]
                for (role, tinted, plain, minimum) in roles {
                    let tinted = try #require(tinted, "\(name) \(role) should be tinted")
                    let floor = min(palette.contrast(plain), minimum)
                    let got = palette.contrast(tinted)
                    #expect(got >= floor - 0.01, "\(name) \(role) in \(scheme): \(got) under \(floor)")
                }
            }
        }
    }
}
