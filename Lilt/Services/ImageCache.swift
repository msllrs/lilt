import AppKit
import Foundation
import SwiftUI

/// In-memory artwork cache in front of a disk-backed URLSession.
///
/// Google thumbnails encode their size in the URL (`=w240-h240-…`), so the same cover at two
/// sizes has two URLs. The cache also indexes by the size-stripped base so a smaller version
/// already on hand can stand in, blurred, while the requested size loads.
@MainActor
final class ImageCache {
    static let shared = ImageCache()

    private let images = NSCache<NSString, NSImage>()
    /// Average colour per cached URL, for balancing ambient shadows and tinting the platter.
    private var averages: [String: (r: CGFloat, g: CGFloat, b: CGFloat)] = [:]
    /// Average luminance of the outer perimeter per cached URL, for picking the keyline colour.
    private var edges: [String: CGFloat] = [:]
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

    /// How bright the artwork is overall. Any measured size of the same cover will do, so the
    /// value is stable from the first frame instead of jumping when this exact URL lands.
    func luminance(for url: URL) -> CGFloat {
        let key = url.absoluteString
        let sample = averages[key] ?? (variants[Self.baseKey(url)] ?? []).lazy.compactMap { self.averages[$0.absoluteString] }.first
        guard let c = sample else { return 0.5 }
        return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
    }

    /// How bright the artwork is along its edges (0 dark … 1 white), which is what a keyline
    /// actually sits against. Falls back to any measured size of the same cover, then mid-grey.
    func edgeLuminance(for url: URL) -> CGFloat {
        edges[url.absoluteString]
            ?? (variants[Self.baseKey(url)] ?? []).lazy.compactMap { self.edges[$0.absoluteString] }.first
            ?? 0.5
    }

    private var thumbnails: [String: NSImage] = [:]

    /// A small rounded rendition for menu items, which otherwise draw images at native size.
    func thumbnail(for url: URL, side: CGFloat = 16, radius: CGFloat = 3) -> NSImage? {
        let key = "\(url.absoluteString)#\(Int(side))"
        if let hit = thumbnails[key] { return hit }
        guard let source = cached(url) ?? anyVariant(for: url) else { return nil }
        let size = NSSize(width: side, height: side)
        let thumb = NSImage(size: size, flipped: false) { rect in
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()
            source.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        thumbnails[key] = thumb
        return thumb
    }

    /// Warm the cache for artwork that's about to appear, so rows render on their first frame
    /// instead of popping in one by one.
    func prefetch(_ urls: [URL?]) {
        for case let url? in urls where cached(url) == nil && inflight[url] == nil {
            Task { _ = await load(url) }
        }
    }

    /// The artwork's average colour with its saturation pushed, for tinting surfaces. Brightness
    /// is kept in a middle band so the tint reads on both light and dark glass.
    func tint(for url: URL, saturationBoost: CGFloat) -> Color? {
        guard let c = averages[url.absoluteString] else { return nil }
        let color = NSColor(red: c.r, green: c.g, blue: c.b, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let adjusted = NSColor(hue: h, saturation: min(1, s * saturationBoost), brightness: min(max(b, 0.35), 0.85), alpha: 1)
        return Color(nsColor: adjusted)
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
        if let average = Self.averageColor(of: image) {
            averages[url.absoluteString] = average
        }
        if let edge = Self.edgeLuminance(of: image) {
            edges[url.absoluteString] = edge
        }
    }

    /// Downsamples to a small grid and averages the outer ring of pixels.
    private static func edgeLuminance(of image: NSImage) -> CGFloat? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let side = 24
        var pixels = [UInt8](repeating: 0, count: side * side)
        guard let context = CGContext(
            data: &pixels, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
        var total = 0, count = 0
        for y in 0..<side {
            for x in 0..<side where x == 0 || y == 0 || x == side - 1 || y == side - 1 {
                total += Int(pixels[y * side + x])
                count += 1
            }
        }
        return count > 0 ? CGFloat(total) / CGFloat(count) / 255 : nil
    }

    /// Draws the image into a single pixel and reads back its average colour.
    private static func averageColor(of image: NSImage) -> (r: CGFloat, g: CGFloat, b: CGFloat)? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return (CGFloat(pixel[0]) / 255, CGFloat(pixel[1]) / 255, CGFloat(pixel[2]) / 255)
    }

    /// The URL with its size parameters removed.
    static func baseKey(_ url: URL) -> String {
        url.absoluteString.replacing(/=w\d+-h\d+[^?#]*/, with: "")
    }
}
