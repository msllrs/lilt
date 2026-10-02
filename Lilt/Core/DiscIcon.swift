import AppKit

/// Draws the Dock tile: the standard macOS icon shape with a compact disc on it, either generic
/// (no track) or carrying the current cover art as its label. The shipped app icon is an Icon
/// Composer `.icon` with the same disc as a glass layer; this mirrors it for the live Dock image.
enum DiscIcon {
    static func genericTile(side: CGFloat = 512) -> NSImage {
        tile(side: side) { rect in drawGenericDisc(in: rect, side: side) }
    }

    static func tile(artwork: NSImage, side: CGFloat = 512) -> NSImage {
        tile(side: side) { rect in drawArtworkDisc(artwork, in: rect, side: side) }
    }

    /// The disc alone on a transparent background, for the `.icon` layer.
    static func discLayer(side: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: side, height: side), flipped: false) { bounds in
            drawGenericDisc(in: bounds.insetBy(dx: side * 0.02, dy: side * 0.02), side: side)
            return true
        }
    }

    // MARK: Tile

    private static func tile(side: CGFloat, disc: @escaping (NSRect) -> Void) -> NSImage {
        NSImage(size: NSSize(width: side, height: side), flipped: false) { bounds in
            // macOS icon grid: the artwork sits inside a 0.8 × 0.8 squircle centred on the canvas.
            let plate = bounds.insetBy(dx: side * 0.1, dy: side * 0.1)
            let path = squircle(in: plate)
            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            // The same light plate as the shipped Icon Composer icon, so the live tile reads as
            // the app icon with a label on it rather than a different icon.
            NSGradient(colorsAndLocations:
                (NSColor(srgbRed: 0.98, green: 0.98, blue: 0.99, alpha: 1), 0),
                (NSColor(srgbRed: 0.93, green: 0.93, blue: 0.95, alpha: 1), 1)
            )?.draw(in: plate, angle: -90)
            NSGraphicsContext.restoreGraphicsState()
            // Hairline edge like the system's icon plate.
            path.lineWidth = side * 0.004
            NSColor(white: 0, alpha: 0.08).setStroke()
            path.stroke()

            // Soft drop shadow under the disc so it sits on the plate.
            let discRect = plate.insetBy(dx: plate.width * 0.10, dy: plate.height * 0.10)
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor(white: 0, alpha: 0.30)
            shadow.shadowBlurRadius = side * 0.03
            shadow.shadowOffset = NSSize(width: 0, height: -side * 0.012)
            shadow.set()
            NSColor.black.setFill()
            NSBezierPath(ovalIn: discRect).fill()
            NSGraphicsContext.restoreGraphicsState()

            disc(discRect)
            return true
        }
    }

    /// Continuous-corner rounded rectangle approximating the system icon shape.
    private static func squircle(in rect: NSRect) -> NSBezierPath {
        NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.2237, yRadius: rect.height * 0.2237)
    }

    // MARK: Discs

    private static func drawGenericDisc(in rect: NSRect, side: CGFloat) {
        let face = NSBezierPath(ovalIn: rect)
        NSGraphicsContext.saveGraphicsState()
        // Brushed silver face with a faint rainbow sheen, the way a blank CD catches light.
        NSGradient(colorsAndLocations:
            (NSColor(white: 0.95, alpha: 1), 0),
            (NSColor(white: 0.80, alpha: 1), 0.55),
            (NSColor(white: 0.64, alpha: 1), 1)
        )?.draw(in: face, relativeCenterPosition: NSPoint(x: -0.25, y: 0.35))
        NSGradient(colorsAndLocations:
            (NSColor(calibratedHue: 0.58, saturation: 0.35, brightness: 1, alpha: 0.30), 0),
            (NSColor(calibratedHue: 0.85, saturation: 0.25, brightness: 1, alpha: 0.18), 0.5),
            (NSColor(calibratedHue: 0.12, saturation: 0.35, brightness: 1, alpha: 0.24), 1)
        )?.draw(in: face, angle: -35)
        NSGraphicsContext.restoreGraphicsState()
        drawChrome(in: rect, side: side)
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

    /// Edge, hub and spindle hole shared by both discs.
    private static func drawChrome(in rect: NSRect, side: CGFloat) {
        let edge = NSBezierPath(ovalIn: rect.insetBy(dx: side * 0.003, dy: side * 0.003))
        edge.lineWidth = side * 0.006
        NSColor(white: 0, alpha: 0.2).setStroke()
        edge.stroke()

        let hubSize = rect.width * 0.26
        let hubRect = NSRect(x: rect.midX - hubSize / 2, y: rect.midY - hubSize / 2, width: hubSize, height: hubSize)
        let hub = NSBezierPath(ovalIn: hubRect)
        NSColor(white: 0.92, alpha: 0.92).setFill()
        hub.fill()
        hub.lineWidth = side * 0.004
        NSColor(white: 0, alpha: 0.15).setStroke()
        hub.stroke()

        let holeSize = rect.width * 0.1
        let holeRect = NSRect(x: rect.midX - holeSize / 2, y: rect.midY - holeSize / 2, width: holeSize, height: holeSize)
        NSGraphicsContext.current?.compositingOperation = .destinationOut
        NSBezierPath(ovalIn: holeRect).fill()
        NSGraphicsContext.current?.compositingOperation = .sourceOver
        let holeEdge = NSBezierPath(ovalIn: holeRect)
        holeEdge.lineWidth = side * 0.004
        NSColor(white: 0, alpha: 0.25).setStroke()
        holeEdge.stroke()
    }
}
