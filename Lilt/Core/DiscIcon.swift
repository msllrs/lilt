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

    @MainActor
    static func tile(artwork: NSImage, side: CGFloat = 1024) -> NSImage {
        let base = base
        return NSImage(size: NSSize(width: side, height: side), flipped: false) { bounds in
            base.draw(in: bounds)
            let plate = bounds.insetBy(dx: side * plateInset, dy: side * plateInset)
            let disc = plate.insetBy(dx: plate.width * discInset, dy: plate.height * discInset)
            drawArtworkDisc(artwork, in: disc, side: side)
            return true
        }
    }

    private static func drawArtworkDisc(_ artwork: NSImage, in rect: NSRect, side: CGFloat) {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(ovalIn: rect).addClip()
        artwork.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        // Soft top-left light so it reads as a physical object, not a flat crop.
        NSGradient(colorsAndLocations:
            (NSColor(white: 1, alpha: 0.26), 0),
            (NSColor(white: 1, alpha: 0.04), 0.5),
            (NSColor(white: 0, alpha: 0.14), 1)
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
