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
    /// Dominant colour per cached URL (nil entry when the cover is effectively grey).
    private var dominants: [String: (r: CGFloat, g: CGFloat, b: CGFloat)?] = [:]
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

    // MARK: Launch artwork

    private static let launchArtworkFile = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("launch-artwork.png")
    private static let launchArtworkKey = "launchArtworkURL"

    /// Keeps this cover on disk as a plain file, so a relaunch can draw the platter and its
    /// colours before the first frame. The URL cache would serve it too, but only after the
    /// session has spun up, which on a cold start is longer than the window takes to appear.
    func rememberForLaunch(_ image: NSImage, for url: URL) {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: Self.launchArtworkFile, options: .atomic)
        UserDefaults.standard.set(url.absoluteString, forKey: Self.launchArtworkKey)
    }

    /// Puts the remembered cover straight into the cache if it is the one asked for.
    func restoreForLaunch(_ url: URL) {
        guard cached(url) == nil, UserDefaults.standard.string(forKey: Self.launchArtworkKey) == url.absoluteString,
              let image = NSImage(contentsOf: Self.launchArtworkFile) else { return }
        store(image, for: url)
    }

    /// How bright the artwork is overall. Any measured size of the same cover will do, so the
    /// value is stable from the first frame instead of jumping when this exact URL lands.
    func luminance(for url: URL) -> CGFloat {
        guard let c = averageColour(for: url) else { return 0.5 }
        return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
    }

    // MARK: Colour lookups

    /// Average colour: this exact URL, any cached size of the same cover, or what was measured
    /// in an earlier session.
    private func averageColour(for url: URL) -> (r: CGFloat, g: CGFloat, b: CGFloat)? {
        if let c = averages[url.absoluteString] { return c }
        let base = Self.baseKey(url)
        if let c = (variants[base] ?? []).lazy.compactMap({ self.averages[$0.absoluteString] }).first { return c }
        return remembered[base]?.average
    }

    private func edgeValue(for url: URL) -> CGFloat? {
        if let e = edges[url.absoluteString] { return e }
        let base = Self.baseKey(url)
        return (variants[base] ?? []).lazy.compactMap { self.edges[$0.absoluteString] }.first ?? remembered[base].map { CGFloat($0.edge) }
    }

    /// Dominant colour entry: `.some(nil)` is a measured grey cover, `nil` is not measured yet.
    private func dominantEntry(for url: URL) -> (r: CGFloat, g: CGFloat, b: CGFloat)?? {
        if let e = dominants[url.absoluteString] { return e }
        let base = Self.baseKey(url)
        if let e = (variants[base] ?? []).lazy.compactMap({ self.dominants[$0.absoluteString] }).first { return e }
        if let r = remembered[base] { return .some(r.dominant) }
        return nil
    }

    /// How bright the artwork is along its edges (0 dark … 1 white), which is what a keyline
    /// actually sits against. Falls back to any measured size of the same cover, then mid-grey.
    func edgeLuminance(for url: URL) -> CGFloat {
        edgeValue(for: url) ?? 0.5
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
        guard let c = averageColour(for: url) else { return nil }
        let color = NSColor(red: c.r, green: c.g, blue: c.b, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let adjusted = NSColor(hue: h, saturation: min(1, s * saturationBoost), brightness: min(max(b, 0.35), 0.85), alpha: 1)
        return Color(nsColor: adjusted)
    }

    /// The artwork's dominant colour, brightened into a band that reads as a line or accent on
    /// both light and dark glass. Nil for covers with no colour to speak of, so callers fall
    /// back to the label colour rather than tinting grey.
    func accent(for url: URL, saturationBoost: CGFloat) -> Color? {
        guard let entry = dominantEntry(for: url), let c = entry else { return nil }
        let color = NSColor(red: c.r, green: c.g, blue: c.b, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let adjusted = NSColor(hue: h, saturation: min(1, s * saturationBoost), brightness: min(max(b, 0.45), 0.8), alpha: 1)
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
        let average = Self.averageColor(of: image)
        if let average { averages[url.absoluteString] = average }
        let edge = Self.edgeLuminance(of: image)
        if let edge { edges[url.absoluteString] = edge }
        let dominant = Self.dominantColor(of: image)
        dominants[url.absoluteString] = dominant
        if let average, let edge { remember(ColourRecord(average: average, edge: edge, dominant: dominant), for: Self.baseKey(url)) }
    }

    // MARK: Remembered colours

    /// What was measured from a cover, kept across launches so a tint can answer before the
    /// image has loaded: the platter, the Play capsule and the page ambient are coloured on
    /// their first frame instead of when the picture lands.
    private struct ColourRecord: Codable {
        var r: Double, g: Double, b: Double, edge: Double
        var dr: Double?, dg: Double?, db: Double?
        init(average: (r: CGFloat, g: CGFloat, b: CGFloat), edge: CGFloat, dominant: (r: CGFloat, g: CGFloat, b: CGFloat)?) {
            r = average.r; g = average.g; b = average.b; self.edge = edge
            dr = dominant.map { Double($0.r) }; dg = dominant.map { Double($0.g) }; db = dominant.map { Double($0.b) }
        }
        var average: (r: CGFloat, g: CGFloat, b: CGFloat) { (CGFloat(r), CGFloat(g), CGFloat(b)) }
        var dominant: (r: CGFloat, g: CGFloat, b: CGFloat)? {
            guard let dr, let dg, let db else { return nil }
            return (CGFloat(dr), CGFloat(dg), CGFloat(db))
        }
    }

    private static let coloursFile = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("artwork-colours.json")
    private static let rememberedLimit = 600
    /// Keyed by the size-stripped URL; insertion order is kept so the oldest can be dropped.
    private lazy var remembered: [String: ColourRecord] = Self.loadRemembered()
    private lazy var rememberedOrder: [String] = Array(remembered.keys)
    private var saveTask: Task<Void, Never>?

    private static func loadRemembered() -> [String: ColourRecord] {
        guard let data = try? Data(contentsOf: coloursFile), let decoded = try? JSONDecoder().decode([String: ColourRecord].self, from: data) else { return [:] }
        return decoded
    }

    private func remember(_ record: ColourRecord, for key: String) {
        if remembered[key] == nil { rememberedOrder.append(key) }
        remembered[key] = record
        while rememberedOrder.count > Self.rememberedLimit { remembered[rememberedOrder.removeFirst()] = nil }
        saveTask?.cancel()
        saveTask = Task { @MainActor [remembered] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let data = try? JSONEncoder().encode(remembered) else { return }
            try? data.write(to: Self.coloursFile, options: .atomic)
        }
    }

    /// Histogram over a small downsample: pixels are binned by hue, saturation and brightness,
    /// each vote weighted by how colourful it is, and the winning bin's mean is the answer. An
    /// average would turn a red-and-blue cover purple; this picks one of them.
    private static func dominantColor(of image: NSImage) -> (r: CGFloat, g: CGFloat, b: CGFloat)? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let side = 24
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let context = CGContext(
            data: &pixels, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))

        struct Bin { var weight: CGFloat = 0; var r: CGFloat = 0; var g: CGFloat = 0; var b: CGFloat = 0 }
        let hueBins = 12, satBins = 2, briBins = 3
        var bins = [Bin](repeating: Bin(), count: hueBins * satBins * briBins)
        var colourful: CGFloat = 0, total: CGFloat = 0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let r = CGFloat(pixels[i]) / 255, g = CGFloat(pixels[i + 1]) / 255, b = CGFloat(pixels[i + 2]) / 255
            let maxC = max(r, g, b), minC = min(r, g, b), delta = maxC - minC
            let sat = maxC > 0 ? delta / maxC : 0
            total += 1
            // Grey and near-black pixels carry no colour information; they only vote weakly.
            guard sat > 0.15, maxC > 0.12 else { continue }
            colourful += 1
            var hue: CGFloat = 0
            if delta > 0 {
                if maxC == r { hue = ((g - b) / delta).truncatingRemainder(dividingBy: 6) }
                else if maxC == g { hue = (b - r) / delta + 2 }
                else { hue = (r - g) / delta + 4 }
                hue /= 6
                if hue < 0 { hue += 1 }
            }
            let h = min(Int(hue * CGFloat(hueBins)), hueBins - 1)
            let sIndex = sat > 0.5 ? 1 : 0
            let bIndex = min(Int(maxC * CGFloat(briBins)), briBins - 1)
            let index = (h * satBins + sIndex) * briBins + bIndex
            // Saturated, mid-bright pixels are what the eye calls "the colour" of a cover.
            let weight = sat * (1 - abs(maxC - 0.6) * 0.8)
            bins[index].weight += weight
            bins[index].r += r * weight
            bins[index].g += g * weight
            bins[index].b += b * weight
        }
        // A cover that is nearly all grey has no dominant colour.
        guard total > 0, colourful / total > 0.08, let best = bins.max(by: { $0.weight < $1.weight }), best.weight > 0 else { return nil }
        return (best.r / best.weight, best.g / best.weight, best.b / best.weight)
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

    /// The same artwork at another size, when the URL carries one (`=w240-h240-…`).
    static func sized(_ url: URL, _ side: Int) -> URL {
        URL(string: url.absoluteString.replacing(/=w\d+-h\d+/, with: "=w\(side)-h\(side)")) ?? url
    }

    /// The URL with its size parameters removed.
    static func baseKey(_ url: URL) -> String {
        url.absoluteString.replacing(/=w\d+-h\d+[^?#]*/, with: "")
    }
}
