import AppKit
import Foundation
import OSLog
import SwiftUI
import UniformTypeIdentifiers

/// In-memory artwork cache in front of a disk-backed URLSession.
///
/// Google thumbnails encode their size in the URL (`=w240-h240-…`), so the same cover at two
/// sizes has two URLs. The cache also indexes by the size-stripped base so a smaller version
/// already on hand can stand in, blurred, while the requested size loads.
@MainActor
final class ImageCache {
    static let shared = ImageCache()

    /// Decoded covers, least recently used first out. A plain store rather than NSCache, whose
    /// limit is a hint and which evicted on heuristics of its own: a log showed it throwing out
    /// hundreds of covers a minute well under budget, which showed as rows re-loading their
    /// covers on every visit.
    private var images: [String: Entry] = [:]
    private var totalCost = 0
    private var tick: UInt64 = 0
    private struct Entry {
        let url: URL
        let image: NSImage
        let cost: Int
        var lastUsed: UInt64
        /// The longest side it was decoded to fit, and whether that was the whole of the
        /// source (which had fewer pixels than asked for, so there is nothing larger to get).
        let pixels: Int
        let whole: Bool

        func serves(_ wanted: Int) -> Bool { whole || pixels >= wanted }
    }
    /// Decoded pixels. Covers are decoded no larger than they're drawn (see `load`), so this
    /// holds thousands of rows' covers, or several hundred heroes'.
    private static let costLimit = 160 * 1024 * 1024
    /// Where making room stops: a quarter of the budget freed at a time.
    private static let lowWaterMark = costLimit / 4 * 3
    /// Average colour per cached URL, for balancing ambient shadows and tinting the platter.
    private var averages: [String: (r: CGFloat, g: CGFloat, b: CGFloat)] = [:]
    /// Average luminance of the outer perimeter per cached URL, for picking the keyline colour.
    private var edges: [String: CGFloat] = [:]
    /// Dominant colour per cached URL (nil entry when the cover is effectively grey).
    private var dominants: [String: (r: CGFloat, g: CGFloat, b: CGFloat)?] = [:]
    /// base key → URLs of the variants currently cached.
    private var variants: [String: [URL]] = [:]
    /// Decodes on their way, by URL and the size asked for.
    private var inflight: [Flight: Task<DecodedArtwork?, Never>] = [:]
    private struct Flight: Hashable {
        let url: URL
        let pixels: Int
    }
    private let session: URLSession

    /// Diagnostics: covers that have been stored, so a miss on one of them can be told apart
    /// from a cover never loaded.
    private var everStored = Set<String>()
    private static let log = Logger(subsystem: "com.msllrs.Lilt", category: "imagecache")

    private init() {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 20 * 1024 * 1024, diskCapacity: 300 * 1024 * 1024)
        config.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: config)
    }

    /// The cover decoded with at least `pixels` on its longer side (or the whole of a smaller
    /// source), or nil: a row's small decode isn't what the hero draws.
    func cached(_ url: URL, pixels: Int) -> NSImage? {
        guard images[url.absoluteString]?.serves(pixels) == true else { return nil }
        return cached(url)
    }

    /// The URLs kept for the cover's other sizes, for tests.
    func variants(of url: URL) -> [URL] { variants[Self.baseKey(url)] ?? [] }

    /// What anything draws a cover at without saying: the hero at 140pt on a 2x display.
    nonisolated static let defaultPixels = 288

    /// Covers are decoded for a 2x display; a 1x one draws from the same decode with pixels
    /// to spare.
    nonisolated static let backingScale: CGFloat = 2

    /// The side, in pixels, a cover drawn at `points` is decoded at: a row's 40pt cover at 80,
    /// where decoded for the hero it cost eight times the memory, and a few hundred library
    /// covers filled the cache and pushed out the ones on screen.
    nonisolated static func pixels(forPoints points: CGFloat) -> Int { Int((points * backingScale).rounded(.up)) }

    /// What a row's cover is decoded at, the size covers are fetched ahead at.
    nonisolated static let rowPixels = pixels(forPoints: Theme.Size.rowArtwork)

    func cached(_ url: URL) -> NSImage? {
        let key = url.absoluteString
        guard let entry = images[key] else {
            if everStored.contains(key) { Self.log.debug("miss on a cover stored earlier: \(key, privacy: .public)") }
            return nil
        }
        tick += 1
        images[key]?.lastUsed = tick
        return entry.image
    }

    /// Makes room for `cost` more, least recently used first. Once over the limit it clears down
    /// to the low-water mark in one sort, so the next hundred or so covers fit without another:
    /// making room only for the one coming in sorted everything held for every cover a shelf
    /// brought in, 19% of the main thread while one opened.
    private func evict(toFit cost: Int) {
        guard totalCost + cost > Self.costLimit else { return }
        for (key, entry) in images.sorted(by: { $0.value.lastUsed < $1.value.lastUsed }) {
            images[key] = nil
            totalCost -= entry.cost
            forgetVariant(entry.url)
            Self.log.debug("evicting \(key, privacy: .public) (\(entry.cost / 1024)KB)")
            if totalCost + cost <= Self.lowWaterMark { break }
        }
    }

    // MARK: Launch artwork

    private static let launchArtworkFile = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("launch-artwork.png")
    private static let launchArtworkKey = "launchArtworkURL"

    /// Files the cache keeps (the launch cover, the remembered colours), written in the order
    /// they were asked for, off the main actor.
    private static let diskQueue = DispatchQueue(label: "com.msllrs.Lilt.imagecache", qos: .utility)

    /// Keeps this cover on disk as a plain file, so a relaunch can draw the platter and its
    /// colours before the first frame. The URL cache would serve it too, but only after the
    /// session has spun up, which on a cold start is longer than the window takes to appear.
    /// Encoded on the disk queue straight from the decoded bitmap: on the main thread, by way
    /// of a TIFF and a bitmap rep, it cost every song change a few milliseconds. The URL is
    /// noted only once the file is written, so the two never disagree.
    func rememberForLaunch(_ image: NSImage, for url: URL) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let picture = UncheckedImage(cgImage: cgImage)
        let file = Self.launchArtworkFile, key = Self.launchArtworkKey, value = url.absoluteString
        Self.diskQueue.async {
            let png = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(png, UTType.png.identifier as CFString, 1, nil) else { return }
            CGImageDestinationAddImage(destination, picture.cgImage, nil)
            guard CGImageDestinationFinalize(destination), (try? (png as Data).write(to: file, options: .atomic)) != nil else { return }
            UserDefaults.standard.set(value, forKey: key)
        }
    }

    /// Waits for the files the cache is writing, a colour save still waiting written now; for
    /// tests.
    func flushToDisk() {
        if saveTask != nil {
            saveTask?.cancel()
            saveTask = nil
            saveRemembered()
        }
        Self.diskQueue.sync {}
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
    /// instead of popping in one by one. Decoded at `pixels`, a row's size unless said.
    func prefetch(_ urls: [URL?], pixels: Int = rowPixels) {
        for case let url? in urls where cached(url, pixels: pixels) == nil && inflight[Flight(url: url, pixels: pixels)] == nil {
            Task { _ = await load(url, maxPixels: pixels) }
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

    /// A rendition thrown out of the cache is no longer one to stand in.
    private func forgetVariant(_ url: URL) {
        let base = Self.baseKey(url)
        variants[base]?.removeAll { $0 == url }
        if variants[base]?.isEmpty == true { variants[base] = nil }
    }

    /// Any cached rendition of the same artwork, regardless of size.
    func anyVariant(for url: URL) -> NSImage? {
        let key = Self.baseKey(url)
        for candidate in variants[key] ?? [] where candidate != url {
            if let image = cached(candidate) { return image }
        }
        return nil
    }

    /// Fetches, decodes and measures the artwork off the main thread; what reaches the main
    /// actor is a finished bitmap and three numbers. Decoded lazily, at first draw, a cover
    /// cost the main thread its decode in the middle of a scroll.
    /// `maxPixels` is the largest side anything will draw the cover at: the hero at 140pt on a
    /// 2x display by default; the Dock tile asks for more. The server's rendition can be far
    /// bigger (576px playlist art, 1280px video thumbnails), and decoded at that size a cover
    /// cost up to 3.7MB, so a couple of hundred of them overran any sensible budget.
    /// A cover already decoded at least that large is the answer; a smaller one is decoded
    /// again at this size, and replaces it.
    func load(_ url: URL, maxPixels: Int = defaultPixels) async -> NSImage? {
        if let hit = cached(url, pixels: maxPixels) { return hit }
        let flight = Flight(url: url, pixels: maxPixels)
        if let task = inflight[flight] { return await task.value?.image }
        let task = Task<DecodedArtwork?, Never>.detached(priority: .utility) { [session] in
            guard let (data, _) = try? await session.data(from: url) else { return nil }
            return DecodedArtwork(data, maxPixels: maxPixels)
        }
        inflight[flight] = task
        let decoded = await task.value
        inflight[flight] = nil
        guard let decoded else { return nil }
        // A decode as large or larger landed meanwhile (the hero's, while a row's was out): it stays.
        if let kept = cached(url, pixels: maxPixels) { return kept }
        store(decoded.image, for: url, pixels: maxPixels, whole: decoded.whole, average: decoded.average, edge: decoded.edge, dominant: decoded.dominant)
        return decoded.image
    }

    /// Caches an image that arrived some other way, measuring it here. It serves drawings up
    /// to its own size.
    func store(_ image: NSImage, for url: URL) {
        let pixels = Int(max(image.size.width, image.size.height))
        store(image, for: url, pixels: pixels, whole: false, average: Self.averageColor(of: image), edge: Self.edgeLuminance(of: image), dominant: Self.dominantColor(of: image))
    }

    private func store(_ image: NSImage, for url: URL, pixels: Int, whole: Bool, average: (r: CGFloat, g: CGFloat, b: CGFloat)?, edge: CGFloat?, dominant: (r: CGFloat, g: CGFloat, b: CGFloat)?) {
        // The image's size is its pixel size (decoded images are built that way, and anything
        // else is 72dpi); the representation's pixel counts come back at display scale and
        // charged every cover four times over, so the budget held a quarter of what it should.
        let cost = Int(image.size.width * image.size.height) * 4
        let key = url.absoluteString
        if let old = images[key] { totalCost -= old.cost }
        evict(toFit: cost)
        tick += 1
        images[key] = Entry(url: url, image: image, cost: cost, lastUsed: tick, pixels: pixels, whole: whole)
        totalCost += cost
        everStored.insert(key)
        // Once per URL: stored again at another decode, it's the same rendition.
        let base = Self.baseKey(url)
        if variants[base]?.contains(url) != true { variants[base, default: []].append(url) }
        if let average { averages[url.absoluteString] = average }
        if let edge { edges[url.absoluteString] = edge }
        dominants[url.absoluteString] = dominant
        if let average, let edge { remember(ColourRecord(average: average, edge: edge, dominant: dominant), for: Self.baseKey(url)) }
    }

    // MARK: Remembered colours

    /// What was measured from a cover, kept across launches so a tint can answer before the
    /// image has loaded: the platter, the Play capsule and the page ambient are coloured on
    /// their first frame instead of when the picture lands.
    private struct ColourRecord: Codable, Sendable {
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
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self else { return }
            saveTask = nil
            saveRemembered()
        }
    }

    /// Writes the remembered colours: taken here, encoded and written on the disk queue, where
    /// encoding six hundred of them held the main thread a second after covers stopped coming.
    private func saveRemembered() {
        let snapshot = remembered, file = Self.coloursFile
        Self.diskQueue.async {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: file, options: .atomic)
        }
    }

    /// Histogram over a small downsample: pixels are binned by hue, saturation and brightness,
    /// each vote weighted by how colourful it is, and the winning bin's mean is the answer. An
    /// average would turn a red-and-blue cover purple; this picks one of them.
    nonisolated static func dominantColor(of image: NSImage) -> (r: CGFloat, g: CGFloat, b: CGFloat)? {
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
    nonisolated static func edgeLuminance(of image: NSImage) -> CGFloat? {
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
    nonisolated static func averageColor(of image: NSImage) -> (r: CGFloat, g: CGFloat, b: CGFloat)? {
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

/// A decoded bitmap handed to the disk queue. CGImage is immutable, so sharing it is safe.
private struct UncheckedImage: @unchecked Sendable {
    let cgImage: CGImage
}

/// Artwork decoded to a bitmap and measured, off the main thread. The image is built from a
/// CGImage decoded immediately, so drawing it later is a copy, not a decode, and no larger
/// than the caller will draw it, so a cover costs what it is worth in the cache.
private struct DecodedArtwork: @unchecked Sendable {
    let image: NSImage
    let average: (r: CGFloat, g: CGFloat, b: CGFloat)?
    let edge: CGFloat?
    let dominant: (r: CGFloat, g: CGFloat, b: CGFloat)?
    /// The source had fewer pixels than asked for, so this is all of it.
    let whole: Bool

    init?(_ data: Data, maxPixels: Int) {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        whole = max(cgImage.width, cgImage.height) < maxPixels
        average = ImageCache.averageColor(of: image)
        edge = ImageCache.edgeLuminance(of: image)
        dominant = ImageCache.dominantColor(of: image)
    }
}
