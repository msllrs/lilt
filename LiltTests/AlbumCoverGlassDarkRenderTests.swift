import AppKit
import SwiftUI
import Testing
@testable import Lilt

/// An album page's dim lines on Glass in dark mode, rendered off-screen over the mid grey the
/// glass shows above a light desktop, with a red cover (Death's The Sound of Perseverance in
/// Matt's screenshot): the header's meta line and a track row's duration, both the tertiary
/// role, and the row's artist line, the secondary. Each is sampled at its strokes' cores (the
/// pixels furthest from the backdrop) and measured against the backdrop.
@MainActor
struct AlbumCoverGlassDarkRenderTests {
    static let backdrop = CoverPaletteGlassDarkTests.backdrop
    static let red = Color(red: 0.85, green: 0.1, blue: 0.1)

    private func render(_ content: some View, size: CGSize) async -> NSBitmapImageRep {
        let auth = AuthService()
        let music = YTMusicClient(auth: auth, fetchPage: { _ in JSONObject(value: [:]) })
        let view = content
            .frame(width: size.width, height: size.height)
            .background(Color(.sRGB, white: Self.backdrop))
            .environment(\.colorScheme, .dark)
            .environment(auth)
            .environment(PlayerService(auth: auth))
            .environment(music)
            .environment(NavigationModel())
        let hosting = NSHostingView(rootView: AnyView(view))
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -10_000, y: -10_000), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        // Render in sRGB, so the bitmap's components are the sRGB the palette asked for. They
        // are read as they are: the rep calls its space calibrated RGB, and converting from
        // that to sRGB moves a 0.5 grey to 0.57.
        window.colorSpace = .sRGB
        window.contentView = hosting
        window.orderFront(nil)
        defer { window.close() }
        for _ in 0..<10 {
            hosting.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(20))
        }
        let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)!
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        return rep
    }

    /// The contrast against the backdrop of the average of the `count` pixels in a region (in
    /// points) that differ most from it in luminance: the cores of the text's strokes.
    private func strokeContrast(_ rep: NSBitmapImageRep, size: CGSize, x: ClosedRange<Double>, y: ClosedRange<Double>, count: Int = 12) -> Double? {
        let scale = Double(rep.pixelsWide) / size.width
        let back = CoverPalette.luminance(Self.backdrop, Self.backdrop, Self.backdrop)
        var pixels: [(lum: Double, r: Double, g: Double, b: Double)] = []
        for py in stride(from: y.lowerBound, to: y.upperBound, by: 0.5) {
            for px in stride(from: x.lowerBound, to: x.upperBound, by: 0.5) {
                guard let c = rep.colorAt(x: Int(px * scale), y: Int(py * scale)) else { continue }
                let (r, g, b) = (Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent))
                pixels.append((CoverPalette.luminance(r, g, b), r, g, b))
            }
        }
        let top = pixels.sorted { abs($0.lum - back) > abs($1.lum - back) }.prefix(count)
        guard !top.isEmpty else { return nil }
        let n = Double(top.count)
        let fore = CoverPalette.luminance(top.map(\.r).reduce(0, +) / n, top.map(\.g).reduce(0, +) / n, top.map(\.b).reduce(0, +) / n)
        return (max(fore, back) + 0.05) / (min(fore, back) + 0.05)
    }

    @Test func glassDarkAlbumDimLinesRead() async throws {
        let palette = CoverPaletteGlassDarkTests.palette(Self.red, .page, .glass)

        // The header's meta line, styled as `BrowseScreen.header` styles it.
        let metaSize = CGSize(width: 200, height: 30)
        let meta = await render(
            Text("Album • 1998").font(.caption).foregroundStyle(palette.style(\.tertiary, or: .tertiary)),
            size: metaSize
        )
        // The backdrop itself, in a corner nothing draws over.
        let ground = try #require(meta.colorAt(x: 2, y: 2))
        #expect(abs(Double(ground.redComponent) - Self.backdrop) < 0.02, "backdrop rendered as \(ground)")
        let metaContrast = try #require(strokeContrast(meta, size: metaSize, x: 40...160, y: 5...25))

        // A track row, as the album lists it.
        let rowSize = CGSize(width: 320, height: 56)
        let track = Track(id: "glass-dark-row", title: "Scavenger of Human Sorrow", artist: "Death", durationText: "6:57")
        let row = await render(
            TrackRow(track: track, isCurrent: false, isPlaying: false) {}.environment(\.coverPalette, palette),
            size: rowSize
        )
        let durationContrast = try #require(strokeContrast(row, size: rowSize, x: 270...318, y: 10...46))
        let artistContrast = try #require(strokeContrast(row, size: rowSize, x: 60...120, y: 28...46))

        print("AlbumCoverGlassDarkRender meta \(String(format: "%.2f", metaContrast)):1 duration \(String(format: "%.2f", durationContrast)):1 artist \(String(format: "%.2f", artistContrast)):1")
        #expect(metaContrast >= CoverPaletteGlassDarkTests.tertiaryFloor, "meta line \(metaContrast):1")
        #expect(durationContrast >= CoverPaletteGlassDarkTests.tertiaryFloor, "duration \(durationContrast):1")
        #expect(artistContrast >= CoverPaletteGlassDarkTests.secondaryFloor, "artist \(artistContrast):1")
    }
}
