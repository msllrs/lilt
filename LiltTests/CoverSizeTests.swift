import AppKit
import Foundation
import Testing
@testable import Lilt

/// Covers are decoded at the size they're drawn: a row's 40pt cover at 80 pixels, where every
/// cover was decoded for the 140pt hero (288 pixels, 330 KB), so a few hundred library covers
/// filled the cache and pushed out what was on screen. A larger drawing of the same cover gets
/// a larger decode rather than the row's, and the cache's list of each cover's sizes neither
/// grows with each store nor keeps sizes it has thrown out.
@MainActor
struct CoverSizeTests {
    /// A 576-pixel cover on disk, the size YouTube Music serves playlist art at, by a URL the
    /// cache fetches like any other.
    private static func coverFile() throws -> URL {
        let side = 576
        let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.6, green: 0.2, blue: 0.3, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        let png = NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cover-\(UUID().uuidString).png")
        try png.write(to: url)
        return url
    }

    private static func side(_ image: NSImage?) -> Int {
        Int(max(image?.size.width ?? 0, image?.size.height ?? 0))
    }

    @Test func aRowsCoverIsDecodedAtTheSizeRowsDrawIt() async throws {
        let url = try Self.coverFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let image = await ImageCache.shared.load(url, maxPixels: ImageCache.pixels(forPoints: Theme.Size.rowArtwork))
        #expect(Self.side(image) == Int(Theme.Size.rowArtwork * 2), "a 40pt row's cover was decoded at \(Self.side(image)) pixels")
    }

    /// The hero drawing a cover a row has already loaded doesn't take the row's small decode.
    @Test func aLargerDrawingIsNotServedTheRowsDecode() async throws {
        let url = try Self.coverFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let heroPixels = ImageCache.pixels(forPoints: 140)
        _ = await ImageCache.shared.load(url, maxPixels: ImageCache.pixels(forPoints: Theme.Size.rowArtwork))
        let cachedForHero = ImageCache.shared.cached(url, pixels: heroPixels)
        #expect(cachedForHero == nil || Self.side(cachedForHero) >= heroPixels, "the hero was handed a \(Self.side(cachedForHero))-pixel cover")
        let hero = await ImageCache.shared.load(url, maxPixels: heroPixels)
        #expect(Self.side(hero) >= heroPixels, "the hero's own load came back at \(Self.side(hero)) pixels")
        // And the row, asking again, takes the larger one rather than going back for its own.
        let row = ImageCache.shared.cached(url, pixels: ImageCache.pixels(forPoints: Theme.Size.rowArtwork))
        #expect(Self.side(row) >= heroPixels, "the row went back to a smaller decode")
    }

    private static func swatch() -> NSImage {
        let image = NSImage(size: NSSize(width: 80, height: 80))
        image.lockFocus()
        NSColor(red: 0.2, green: 0.5, blue: 0.3, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 80, height: 80).fill()
        image.unlockFocus()
        return image
    }

    @Test func storingACoverAgainDoesNotGrowItsSizes() {
        let url = URL(string: "https://lh3.googleusercontent.com/test-\(UUID().uuidString)=w240-h240-l90-rj")!
        let image = Self.swatch()
        for _ in 0..<10 { ImageCache.shared.store(image, for: url) }
        #expect(ImageCache.shared.variants(of: url) == [url], "ten stores of one cover listed \(ImageCache.shared.variants(of: url).count) sizes")
    }

    @Test func aCoverThrownOutLeavesItsSizes() {
        let run = UUID().uuidString
        let first = URL(string: "https://lh3.googleusercontent.com/test-\(run)-first=w240-h240-l90-rj")!
        let image = Self.swatch()
        ImageCache.shared.store(image, for: first)
        // Past the 160 MB budget at 288 × 288, so the first cover is the oldest and thrown out.
        let big = NSImage(size: NSSize(width: 288, height: 288))
        for i in 0..<700 {
            ImageCache.shared.store(big, for: URL(string: "https://lh3.googleusercontent.com/test-\(run)-fill-\(i)=w240-h240-l90-rj")!)
        }
        #expect(ImageCache.shared.cached(first) == nil, "the first cover was thrown out")
        #expect(ImageCache.shared.variants(of: first).isEmpty, "a cover thrown out still lists \(ImageCache.shared.variants(of: first).count) sizes")
    }

    /// The library's covers fetched ahead are bounded: at a row's size they take no more than
    /// a quarter of the cache, however big the library, and each shelf's first ones are among
    /// them.
    @Test func theLibrarysCoversAheadAreBounded() {
        func shelf(_ kind: BrowseKind, _ name: String) -> [BrowseItem] {
            (0..<3_000).map { BrowseItem(id: "\(name)-\($0)", kind: kind, title: "\($0)", subtitle: "",
                                         artworkURL: URL(string: "https://lh3.googleusercontent.com/\(name)-\($0)=w240-h240")) }
        }
        let content = LibraryContent(playlists: shelf(.playlist, "p"), albums: shelf(.album, "a"), artists: shelf(.artist, "r"))
        let ahead = YTMusicClient.coversAhead(of: content).compactMap { $0 }
        let rowCost = Int(Theme.Size.rowArtwork * 2) * Int(Theme.Size.rowArtwork * 2) * 4
        #expect(ahead.count * rowCost <= 40 * 1024 * 1024, "\(ahead.count) covers ahead, \(ahead.count * rowCost / 1024 / 1024) MB at a row's size")
        for first in [content.playlists[0], content.albums[0], content.artists[0]] {
            #expect(ahead.contains(first.artworkURL!), "\(first.id) leads its shelf")
        }
    }
}
