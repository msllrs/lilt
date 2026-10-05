import AppKit
import Foundation
import Observation

/// Recently played tracks and recently opened pages, most recent first, persisted across
/// launches. Feeds the clock menu beside the search field.
@MainActor
@Observable
final class RecentsStore {
    private static let key = "recents"
    private static let limit = 8

    private(set) var played: [Track] = []
    private(set) var viewed: [BrowseItem] = []
    /// Menu icons, keyed by entry id, kept as PNG files so they survive relaunches and cache
    /// eviction; the menu can't wait for a load once it is open.
    private(set) var thumbnails: [String: NSImage] = [:]
    private static let thumbnailSide: CGFloat = 16
    private static let thumbnailDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("recents-thumbnails", isDirectory: true)

    var isEmpty: Bool { played.isEmpty && viewed.isEmpty }

    private struct Saved: Codable {
        var played: [Track]
        var viewed: [BrowseItem]
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            played = saved.played
            viewed = saved.viewed.filter { $0.kind != .library }
        }
        loadThumbnails()
        // Anything still missing an icon (recorded before icons were kept) gets one now.
        for track in played { captureThumbnail(id: track.id, url: track.artworkURL) }
        for item in viewed { captureThumbnail(id: item.id, url: item.artworkURL) }
    }

    /// `artwork` is the best cover known for the track right now (the web player's live
    /// metadata when the track itself carries none).
    func recordPlayed(_ track: Track, artwork: URL? = nil) {
        var track = track
        if track.artworkURL == nil { track.artworkURL = artwork }
        played.removeAll { $0.id == track.id }
        played.insert(track, at: 0)
        played = Array(played.prefix(Self.limit))
        save()
        captureThumbnail(id: track.id, url: track.artworkURL)
    }

    /// A cover that arrived after the track was recorded (the live metadata lags a beat).
    func updateArtwork(forPlayed id: String, url: URL?) {
        guard let url, let index = played.firstIndex(where: { $0.id == id }), played[index].artworkURL == nil else { return }
        played[index].artworkURL = url
        save()
        captureThumbnail(id: id, url: url)
    }

    func recordViewed(_ item: BrowseItem) {
        // The library has its own button; it isn't something you "found" and want to get back to.
        guard item.kind != .library else { return }
        viewed.removeAll { $0.id == item.id || $0.kind == .library }
        viewed.insert(item, at: 0)
        viewed = Array(viewed.prefix(Self.limit))
        save()
        captureThumbnail(id: item.id, url: item.artworkURL)
    }

    func clear() {
        played = []
        viewed = []
        thumbnails = [:]
        try? FileManager.default.removeItem(at: Self.thumbnailDirectory)
        save()
    }

    // MARK: Thumbnails

    func thumbnail(for id: String) -> NSImage? { thumbnails[id] }

    private static func thumbnailFile(for id: String) -> URL {
        let name = id.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : "_" }.joined()
        return thumbnailDirectory.appendingPathComponent(name + ".png")
    }

    /// Loads the thumbnails on disk for the current entries.
    private func loadThumbnails() {
        for id in played.map(\.id) + viewed.map(\.id) {
            guard thumbnails[id] == nil, let image = NSImage(contentsOf: Self.thumbnailFile(for: id)) else { continue }
            image.size = NSSize(width: Self.thumbnailSide, height: Self.thumbnailSide)
            thumbnails[id] = image
        }
    }

    /// Renders and stores the menu icon for an entry once its cover is loaded. Cheap to call
    /// again: it does nothing when the icon already exists.
    func captureThumbnail(id: String, url: URL?) {
        guard thumbnails[id] == nil, let url else { return }
        Task { @MainActor in
            guard let source = await ImageCache.shared.load(url) else { return }
            let side = Self.thumbnailSide, scale: CGFloat = 2
            let pixels = Int(side * scale)
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
            rep.size = NSSize(width: side, height: side)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            let rect = NSRect(x: 0, y: 0, width: side, height: side)
            NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).addClip()
            source.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
            let image = NSImage(size: rect.size)
            image.addRepresentation(rep)
            thumbnails[id] = image
            try? FileManager.default.createDirectory(at: Self.thumbnailDirectory, withIntermediateDirectories: true)
            if let png = rep.representation(using: .png, properties: [:]) { try? png.write(to: Self.thumbnailFile(for: id), options: .atomic) }
        }
    }

    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(Saved(played: played, viewed: viewed)), forKey: Self.key)
    }
}
