import AppKit
import Foundation
import Testing
@testable import Lilt

/// The cover cache's two files, the playing cover kept for the next launch and the colours
/// measured from covers, are encoded and written off the main thread, and still come back.
/// The test host shares the app's container, so each test puts back what it found there.
@MainActor
@Suite(.serialized)
struct CoverFilesTests {
    private static let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]

    /// Runs `body`, then puts `file` and the default under `key` back as they were.
    private static func preserving(_ file: String, default key: String? = nil, _ body: () async throws -> Void) async rethrows {
        let url = caches.appendingPathComponent(file)
        let saved = try? Data(contentsOf: url)
        let savedDefault = key.flatMap { UserDefaults.standard.object(forKey: $0) }
        defer {
            ImageCache.shared.flushToDisk()
            if let saved { try? saved.write(to: url, options: .atomic) } else { try? FileManager.default.removeItem(at: url) }
            if let key { UserDefaults.standard.set(savedDefault, forKey: key) }
        }
        try await body()
    }

    private static func cover(_ side: Int) -> NSImage {
        let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.7, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        return NSImage(cgImage: context.makeImage()!, size: NSSize(width: side, height: side))
    }

    @Test func thePlayingCoverIsThereForTheNextLaunch() async throws {
        try await Self.preserving("launch-artwork.png", default: "launchArtworkURL") {
            let url = URL(string: "https://lh3.googleusercontent.com/test-launch-\(UUID().uuidString)=w240-h240")!
            ImageCache.shared.rememberForLaunch(Self.cover(288), for: url)
            ImageCache.shared.flushToDisk()
            #expect(UserDefaults.standard.string(forKey: "launchArtworkURL") == url.absoluteString)
            ImageCache.shared.restoreForLaunch(url)
            let restored = ImageCache.shared.cached(url)
            #expect(restored?.size == NSSize(width: 288, height: 288), "the next launch drew \(String(describing: restored?.size))")
        }
    }

    /// The test host's colours go to a file of their own, away from the app's.
    @Test func aCoversColoursAreRemembered() async throws {
        #expect(ImageCache.coloursFile.lastPathComponent != "artwork-colours.json", "the tests' made-up covers stay out of the app's file")
        try await Self.preserving(ImageCache.coloursFile.lastPathComponent) {
            let url = URL(string: "https://lh3.googleusercontent.com/test-colours-\(UUID().uuidString)=w240-h240")!
            ImageCache.shared.store(Self.cover(80), for: url)
            ImageCache.shared.flushToDisk()
            let data = try Data(contentsOf: ImageCache.coloursFile)
            let saved = try JSONDecoder().decode([String: [String: Double]].self, from: data)
            let record = saved[ImageCache.baseKey(url)]
            #expect(record != nil, "the cover's colours were written")
            #expect(abs((record?["b"] ?? 0) - 0.7) < 0.1, "its average colour: \(record ?? [:])")
        }
    }
}
