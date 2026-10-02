import AppKit

/// Draws the Dock icon: a compact disc, either generic (no track) or carrying the current
/// cover art as its label.
enum DiscIcon {
    static func generic(side: CGFloat = 512) -> NSImage {
        render(side: side) { rect in
            // Brushed silver face with a faint rainbow sheen, the way a blank CD catches light.
            let face = NSBezierPath(ovalIn: rect)
            NSGradient(colorsAndLocations:
                (NSColor(white: 0.93, alpha: 1), 0),
                (NSColor(white: 0.78, alpha: 1), 0.55),
                (NSColor(white: 0.62, alpha: 1), 1)
            )?.draw(in: face, relativeCenterPosition: NSPoint(x: -0.25, y: 0.35))
            let sheen = NSGradient(colorsAndLocations:
                (NSColor(calibratedHue: 0.58, saturation: 0.35, brightness: 1, alpha: 0.28), 0),
                (NSColor(calibratedHue: 0.85, saturation: 0.25, brightness: 1, alpha: 0.18), 0.5),
                (NSColor(calibratedHue: 0.12, saturation: 0.35, brightness: 1, alpha: 0.22), 1)
            )
            sheen?.draw(in: face, angle: -35)
        }
    }

    static func disc(artwork: NSImage, side: CGFloat = 512) -> NSImage {
        render(side: side) { rect in
            NSBezierPath(ovalIn: rect).addClip()
            artwork.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            // Soft top-left light so it reads as a physical object, not a flat crop.
            NSGradient(colorsAndLocations:
                (NSColor(white: 1, alpha: 0.28), 0),
                (NSColor(white: 1, alpha: 0.04), 0.5),
                (NSColor(white: 0, alpha: 0.12), 1)
            )?.draw(in: NSBezierPath(ovalIn: rect), angle: -60)
        }
    }

    /// Common chrome: outer edge, label ring and spindle hole.
    private static func render(side: CGFloat, face: @escaping (NSRect) -> Void) -> NSImage {
        NSImage(size: NSSize(width: side, height: side), flipped: false) { bounds in
            let inset = side * 0.03
            let rect = bounds.insetBy(dx: inset, dy: inset)
            NSGraphicsContext.saveGraphicsState()
            face(rect)
            NSGraphicsContext.restoreGraphicsState()

            // Edge.
            let edge = NSBezierPath(ovalIn: rect.insetBy(dx: side * 0.004, dy: side * 0.004))
            edge.lineWidth = side * 0.008
            NSColor(white: 0, alpha: 0.18).setStroke()
            edge.stroke()

            // Hub and hole.
            let hubRect = NSRect(x: bounds.midX - side * 0.11, y: bounds.midY - side * 0.11, width: side * 0.22, height: side * 0.22)
            let hub = NSBezierPath(ovalIn: hubRect)
            NSColor(white: 0.92, alpha: 0.9).setFill()
            hub.fill()
            hub.lineWidth = side * 0.006
            NSColor(white: 0, alpha: 0.15).setStroke()
            hub.stroke()
            let holeRect = NSRect(x: bounds.midX - side * 0.045, y: bounds.midY - side * 0.045, width: side * 0.09, height: side * 0.09)
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            NSBezierPath(ovalIn: holeRect).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            let holeEdge = NSBezierPath(ovalIn: holeRect)
            holeEdge.lineWidth = side * 0.006
            NSColor(white: 0, alpha: 0.25).setStroke()
            holeEdge.stroke()
            return true
        }
    }
}
