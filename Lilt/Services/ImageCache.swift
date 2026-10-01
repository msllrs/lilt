import AppKit
import Foundation

/// In-memory artwork cache in front of a disk-backed URLSession.
///
/// Google thumbnails encode their size in the URL (`=w240-h240-…`), so the same cover at two
/// sizes has two URLs. The cache also indexes by the size-stripped base so a smaller version
/// already on hand can stand in, blurred, while the requested size loads.
@MainActor
final class ImageCache {
    static let shared = ImageCache()

    private let images = NSCache<NSString, NSImage>()
    /// Average luminance (0 dark … 1 white) per cached URL, for balancing ambient shadows.
    private var luminances: [String: CGFloat] = [:]
    /// base key → URLs of the variants currently cached.
    private var variants: [String: [URL]] = [:]
    private var inflight: [URL: Task<NSImage?, Never>] = [:]
    private let session: URLSession

    private init() {
        images.totalCostLimit = 120 * 1024 * 1024
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 20 * 1024 * 1024, diskCapacity: 300 * 1024 * 1024)
        config.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: config)
    }

    func cached(_ url: URL) -> NSImage? {
        images.object(forKey: url.absoluteString as NSString)
    }

    /// How bright the artwork is overall, when we've seen it (falls back to mid-grey).
    func luminance(for url: URL) -> CGFloat {
        luminances[url.absoluteString] ?? 0.5
    }

    /// Any cached rendition of the same artwork, regardless of size.
    func anyVariant(for url: URL) -> NSImage? {
        let key = Self.baseKey(url)
        for candidate in variants[key] ?? [] where candidate != url {
            if let image = cached(candidate) { return image }
        }
        return nil
    }

    func load(_ url: URL) async -> NSImage? {
        if let hit = cached(url) { return hit }
        if let task = inflight[url] { return await task.value }
        let task = Task<NSImage?, Never> { [session] in
            guard let (data, _) = try? await session.data(from: url), let image = NSImage(data: data) else { return nil }
            return image
        }
        inflight[url] = task
        let image = await task.value
        inflight[url] = nil
        if let image { store(image, for: url) }
        return image
    }

    private func store(_ image: NSImage, for url: URL) {
        let pixels = image.representations.first.map { $0.pixelsWide * $0.pixelsHigh } ?? Int(image.size.width * image.size.height)
        images.setObject(image, forKey: url.absoluteString as NSString, cost: pixels * 4)
        variants[Self.baseKey(url), default: []].append(url)
        if let luminance = Self.averageLuminance(of: image) {
            luminances[url.absoluteString] = luminance
        }
    }

    /// Draws the image into a single pixel and reads back its relative luminance.
    private static func averageLuminance(of image: NSImage) -> CGFloat? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let r = CGFloat(pixel[0]) / 255, g = CGFloat(pixel[1]) / 255, b = CGFloat(pixel[2]) / 255
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    /// The URL with its size parameters removed.
    static func baseKey(_ url: URL) -> String {
        url.absoluteString.replacing(/=w\d+-h\d+[^?#]*/, with: "")
    }
}
