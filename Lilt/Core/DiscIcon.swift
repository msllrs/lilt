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
    /// - Parameter accent: the cover's colour, for the plate wash and the disc's ambient shadow.
    /// - Parameter scale: pixels per point. The spinning tile draws 128pt at 2x, the same pixels
    ///   as 256pt at 1x for half the cost of handing each frame to the Dock.
    /// - Parameter angle: how far the cover has turned, in degrees clockwise. Only the cover
    ///   turns; the light on it, the hub and the plate stay put.
    @MainActor
    static func tile(artwork: NSImage, edgeLuminance: CGFloat, accent: NSColor?, side: CGFloat = 512, scale: CGFloat = 1, angle: CGFloat = 0) -> NSImage {
        // A single, already rasterised bitmap. A drawing-handler image gets re-rendered at every
        // size AppKit wants when it hands the icon to the Dock.
        let pixels = Int(side * scale)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        // The bitmap context's user space is the rep's point size, so everything below draws in
        // `side` units whatever the scale. The Dock scales the image to its tile.
        rep.size = NSSize(width: side, height: side)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        let bounds = NSRect(x: 0, y: 0, width: side, height: side)
        base.draw(in: bounds)
        let plate = bounds.insetBy(dx: side * plateInset, dy: side * plateInset)
        let disc = plate.insetBy(dx: plate.width * discInset, dy: plate.height * discInset)
        if let accent {
            drawPlateTint(accent, in: plate)
            drawDiscShadow(accent, under: disc)
        }
        drawArtworkDisc(artwork, in: disc, edgeLuminance: edgeLuminance, side: side, angle: angle)
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }

    /// The cover on the disc with the same finish as artwork in the app (see ArtworkView): the
    /// spotlight from the top edge in plus-lighter, and the adaptive hairline keyline.
    @MainActor
    private static func drawArtworkDisc(_ artwork: NSImage, in rect: NSRect, edgeLuminance: CGFloat, side: CGFloat, angle: CGFloat) {
        let style = ArtworkStyle.shared
        let face = NSBezierPath(ovalIn: rect)
        NSGraphicsContext.saveGraphicsState()
        face.addClip()
        NSGraphicsContext.saveGraphicsState()
        // This context's y runs up, so clockwise is a negative rotation.
        let turn = NSAffineTransform()
        turn.translateX(by: rect.midX, yBy: rect.midY)
        turn.rotate(byDegrees: -angle)
        turn.translateX(by: -rect.midX, yBy: -rect.midY)
        turn.concat()
        artwork.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        if style.spotlightOpacity > 0, let cg = NSGraphicsContext.current?.cgContext {
            cg.saveGState()
            cg.setBlendMode(blendMode(style.spotlightBlend))
            let colors = [
                CGColor(gray: 1, alpha: style.spotlightOpacity),
                CGColor(gray: 1, alpha: style.spotlightOpacity * 0.35),
                CGColor(gray: 1, alpha: 0),
            ] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceGray(), colors: colors, locations: [0, 0.45, 1]) {
                // SwiftUI's UnitPoint y runs down; this context's y runs up.
                let center = CGPoint(x: rect.minX + rect.width * style.spotlightCenterX, y: rect.maxY - rect.height * style.spotlightCenterY)
                cg.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: rect.width * style.spotlightRadius, options: [])
            }
            cg.restoreGState()
        }
        NSGraphicsContext.restoreGraphicsState()

        // Keyline just inside the edge (dark on pale art, light on dark), separator just outside.
        // Scaled so it stays a hairline at Dock sizes, roughly one point at 2x.
        let line = side / 256
        let keyline: NSColor? = switch style.keylineMode {
        case .off: nil
        case .dark: NSColor(white: 0, alpha: style.keylineDarkOpacity)
        case .light: NSColor(white: 1, alpha: style.keylineLightOpacity)
        case .adaptive: edgeLuminance > style.keylineThreshold
            ? NSColor(white: 0, alpha: style.keylineDarkOpacity)
            : NSColor(white: 1, alpha: style.keylineLightOpacity)
        }
        if let keyline {
            let inner = NSBezierPath(ovalIn: rect.insetBy(dx: line / 2, dy: line / 2))
            inner.lineWidth = line
            keyline.setStroke()
            inner.stroke()
        }
        if style.separatorOpacity > 0 {
            let outer = NSBezierPath(ovalIn: rect.insetBy(dx: -line / 2, dy: -line / 2))
            outer.lineWidth = line
            NSColor(white: 0, alpha: style.separatorOpacity).setStroke()
            outer.stroke()
        }
        drawHub(in: rect, side: side)
    }

    /// The cover's colour washed over the plate, light at the top and strongest at the bottom
    /// (the plate's own gradient runs the same way), inside the system's squircle so the
    /// rendered rim and shadow stay untouched.
    @MainActor
    private static func drawPlateTint(_ accent: NSColor, in plate: NSRect) {
        let style = ArtworkStyle.shared.dockTile
        guard style.plateTint > 0 else { return }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        accent.usingColorSpace(.sRGB)?.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let colour = NSColor(hue: h, saturation: min(1, s * style.plateSaturation), brightness: max(b, 0.6), alpha: 1)
        NSGraphicsContext.saveGraphicsState()
        // Icon plate corners: the system shape, close enough to a continuous curve at 22.37%.
        NSBezierPath(roundedRect: plate, xRadius: plate.width * 0.2237, yRadius: plate.height * 0.2237).addClip()
        NSGradient(colorsAndLocations:
            (colour.withAlphaComponent(style.plateTint * 0.35), 0),
            (colour.withAlphaComponent(style.plateTint), 1)
        )?.draw(in: plate, angle: -90)
        NSGraphicsContext.restoreGraphicsState()
    }

    /// A coloured ambient shadow under the disc, like the artwork shadows in the app: the cover's
    /// colour, blurred, sitting a little low.
    @MainActor
    private static func drawDiscShadow(_ accent: NSColor, under disc: NSRect) {
        let style = ArtworkStyle.shared.dockTile
        guard style.shadowOpacity > 0 else { return }
        NSGraphicsContext.saveGraphicsState()
        // Only the shadow is wanted: clip the fill itself away.
        let outside = NSBezierPath(rect: disc.insetBy(dx: -disc.width, dy: -disc.height))
        outside.append(NSBezierPath(ovalIn: disc).reversed)
        outside.addClip()
        let shadow = NSShadow()
        shadow.shadowColor = accent.withAlphaComponent(style.shadowOpacity)
        shadow.shadowBlurRadius = disc.width * style.shadowBlur
        shadow.shadowOffset = NSSize(width: 0, height: -disc.height * style.shadowOffsetY)
        shadow.set()
        accent.setFill()
        NSBezierPath(ovalIn: disc).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func blendMode(_ blend: ArtworkBlend) -> CGBlendMode {
        switch blend {
        case .plusLighter: .plusLighter
        case .softLight: .softLight
        case .screen: .screen
        case .overlay: .overlay
        case .normal: .normal
        }
    }

    /// Hub and spindle hole, matching the generic disc in the shipped icon.
    private static func drawHub(in rect: NSRect, side: CGFloat) {
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
