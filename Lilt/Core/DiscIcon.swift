import AppKit

/// The live Dock tile while a track plays: the app icon exactly as macOS renders it (plate
/// gradient, rim highlight, the glass disc's shadow, the drop shadow), with the cover art laid
/// onto the disc. Drawing our own plate would lose all of that treatment, which is what made the
/// old tile look flat next to other apps' icons.
enum DiscIcon {
    /// Where the renderer puts the plate inside an icon image, and the disc layer inside the plate
    /// (the Icon Composer canvas maps onto the plate; disc.png is inset 10% of that canvas).
    private static let plateInset: CGFloat = 100 / 1024
    private static let discInset: CGFloat = 0.10

    /// The system's rendering of this bundle's icon: the same image Finder and the Dock show.
    @MainActor private static let base = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)

    /// - Parameter side: 512 keeps the cover crisp at the largest Dock tile and in ⌘-Tab.
    @MainActor
    static func tile(artwork: NSImage, side: CGFloat = 512) -> NSImage {
        // A single, already rasterised bitmap. A drawing-handler image gets re-rendered at every
        // size AppKit wants when it hands the icon to the Dock.
        let pixels = Int(side)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        // Points equal pixels here: the bitmap context's user space is the rep's point size, and
        // everything below draws in `side` units. The Dock scales a 256pt image to its tile.
        rep.size = NSSize(width: side, height: side)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        let bounds = NSRect(x: 0, y: 0, width: side, height: side)
        base.draw(in: bounds)
        let plate = bounds.insetBy(dx: side * plateInset, dy: side * plateInset)
        let disc = plate.insetBy(dx: plate.width * discInset, dy: plate.height * discInset)
        drawArtworkDisc(artwork, in: disc, side: side)
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }

    private static func drawArtworkDisc(_ artwork: NSImage, in rect: NSRect, side: CGFloat) {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(ovalIn: rect).addClip()
        artwork.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        // A faint top-left light so it reads as a physical object; kept light enough that the
        // cover keeps its contrast.
        NSGradient(colorsAndLocations:
            (NSColor(white: 1, alpha: 0.14), 0),
            (NSColor(white: 1, alpha: 0.0), 0.45),
            (NSColor(white: 0, alpha: 0.06), 1)
        )?.draw(in: NSBezierPath(ovalIn: rect), angle: -60)
        NSGraphicsContext.restoreGraphicsState()
        drawChrome(in: rect, side: side)
    }

    /// Edge, hub and spindle hole, matching the generic disc in the shipped icon.
    private static func drawChrome(in rect: NSRect, side: CGFloat) {
        let edge = NSBezierPath(ovalIn: rect.insetBy(dx: side * 0.002, dy: side * 0.002))
        edge.lineWidth = side * 0.005
        NSColor(white: 0, alpha: 0.28).setStroke()
        edge.stroke()
        let inner = NSBezierPath(ovalIn: rect.insetBy(dx: side * 0.008, dy: side * 0.008))
        inner.lineWidth = side * 0.003
        NSColor(white: 1, alpha: 0.5).setStroke()
        inner.stroke()

        let hubSize = rect.width * 0.30
        let hubRect = NSRect(x: rect.midX - hubSize / 2, y: rect.midY - hubSize / 2, width: hubSize, height: hubSize)
        let hub = NSBezierPath(ovalIn: hubRect)
        NSColor(white: 0.96, alpha: 0.9).setFill()
        hub.fill()
        hub.lineWidth = side * 0.004
        NSColor(white: 0, alpha: 0.18).setStroke()
        hub.stroke()

        let holeSize = rect.width * 0.12
        let holeRect = NSRect(x: rect.midX - holeSize / 2, y: rect.midY - holeSize / 2, width: holeSize, height: holeSize)
        NSGraphicsContext.current?.compositingOperation = .destinationOut
        NSBezierPath(ovalIn: holeRect).fill()
        NSGraphicsContext.current?.compositingOperation = .sourceOver
        let lip = NSBezierPath(ovalIn: holeRect)
        lip.lineWidth = side * 0.004
        NSColor(white: 0, alpha: 0.3).setStroke()
        lip.stroke()
    }
}
