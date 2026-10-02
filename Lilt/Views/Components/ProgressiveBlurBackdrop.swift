import AppKit
import QuartzCore
import SwiftUI

/// A real progressive blur: a Core Animation backdrop layer whose blur radius ramps from full at
/// the top to nothing at the bottom, with the system materials' saturation boost. This is how
/// the Dock and Control Center do it, but through private classes (`CABackdropLayer`, `CAFilter`
/// with the `variableBlur` type), so everything is looked up at runtime and `isAvailable` gates
/// its use; callers fall back to a masked system material when it is false.
struct ProgressiveBlurBackdrop: NSViewRepresentable {
    /// Blur radius in points at the top.
    var radius: Double
    var saturation: Double
    /// Brightness shift (-1...1).
    var brightness: Double
    /// Fraction of the height over which the effect is at full strength before fading out.
    var fadeStart: Double

    /// True when the private classes exist and accept the filter we need.
    static let isAvailable: Bool = {
        guard NSClassFromString("CABackdropLayer") is CALayer.Type else { return false }
        return makeFilter("variableBlur") != nil
    }()

    func makeNSView(context: Context) -> BackdropHostView { BackdropHostView() }

    func updateNSView(_ view: BackdropHostView, context: Context) {
        view.configure(radius: radius, saturation: saturation, brightness: brightness, fadeStart: fadeStart)
    }

    /// `+[CAFilter filterWithType:]`, reached dynamically.
    fileprivate static func makeFilter(_ type: String) -> NSObject? {
        guard let cls = NSClassFromString("CAFilter") as? NSObject.Type else { return nil }
        let selector = NSSelectorFromString("filterWithType:")
        guard cls.responds(to: selector) else { return nil }
        return cls.perform(selector, with: type)?.takeUnretainedValue() as? NSObject
    }
}

final class BackdropHostView: NSView {
    private var backdrop: CALayer?
    private var fade = CAGradientLayer()
    private var blur: NSObject?
    private var radius = 0.0, saturation = 1.0, brightness = 0.0
    private var maskSize = CGSize.zero

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        guard let type = NSClassFromString("CABackdropLayer") as? CALayer.Type else { return }
        let layer = type.init()
        // The blur never needs full resolution; half is what the system uses for its materials.
        if layer.responds(to: NSSelectorFromString("setScale:")) { layer.setValue(0.5, forKey: "scale") }
        fade.startPoint = CGPoint(x: 0.5, y: 1)
        fade.endPoint = CGPoint(x: 0.5, y: 0)
        layer.mask = fade
        self.layer?.addSublayer(layer)
        backdrop = layer
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { false }

    /// The layer runs past the view on the top and sides. Its outermost pixels are never fully
    /// blurred (the half-resolution pass and edge normalisation both leave a sliver), and the
    /// column's rounded clip hides anything beyond the panel, so the visible edge is the clip,
    /// not the layer.
    private static let bleed: CGFloat = 12
    private var fadeStart: CGFloat = 1

    override func layout() {
        super.layout()
        let frame = NSRect(x: -Self.bleed, y: 0, width: bounds.width + Self.bleed * 2, height: bounds.height + Self.bleed)
        backdrop?.frame = frame
        fade.frame = backdrop?.bounds ?? frame
        applyFade()
        applyFilters()
    }

    /// The fade's locations are fractions of the layer, which is taller than the view by the
    /// bleed; convert from the view-relative fraction the caller knows about.
    private func applyFade() {
        let height = bounds.height + Self.bleed
        guard height > 0 else { return }
        let start = (Self.bleed + fadeStart * bounds.height) / height
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fade.colors = [NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
        fade.locations = [0, NSNumber(value: Double(start)), 1]
        CATransaction.commit()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        applyFilters()
    }

    func configure(radius: Double, saturation: Double, brightness: Double, fadeStart: Double) {
        guard backdrop != nil else { return }
        let changed = radius != self.radius || saturation != self.saturation || brightness != self.brightness
        self.radius = radius; self.saturation = saturation; self.brightness = brightness
        // The whole effect fades out below `fadeStart`, so rows melt into it instead of meeting
        // a hard line where the blur stops.
        self.fadeStart = fadeStart
        applyFade()
        if changed { maskSize = .zero; applyFilters() }
    }

    /// The filter maps its mask image 1:1 in pixels (it does not stretch it), so the mask is
    /// rebuilt at the layer's pixel size whenever that changes, and the filters are reassigned
    /// because the layer only picks up a new filter array, not edits to a filter in place.
    private func applyFilters() {
        guard let backdrop, bounds.width > 0, bounds.height > 0 else { return }
        let scale = window?.backingScaleFactor ?? 2
        let size = CGSize(width: (backdrop.bounds.width * scale).rounded(), height: (backdrop.bounds.height * scale).rounded())
        guard size != maskSize else { return }
        maskSize = size
        var filters: [Any] = []
        if let blur = ProgressiveBlurBackdrop.makeFilter("variableBlur"), let mask = Self.rampMask(size: size) {
            blur.setValue(radius, forKey: "inputRadius")
            blur.setValue(mask, forKey: "inputMaskImage")
            blur.setValue(true, forKey: "inputNormalizeEdges")
            filters.append(blur)
        }
        if saturation != 1, let sat = ProgressiveBlurBackdrop.makeFilter("colorSaturate") {
            sat.setValue(saturation, forKey: "inputAmount")
            filters.append(sat)
        }
        if brightness != 0, let bright = ProgressiveBlurBackdrop.makeFilter("colorBrightness") {
            bright.setValue(brightness, forKey: "inputAmount")
            filters.append(bright)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backdrop.filters = filters
        CATransaction.commit()
    }

    /// The variable blur's mask at the layer's pixel size. The filter reads the mask's alpha:
    /// opaque means the full radius, clear means none, so this is a transparency ramp from the
    /// top down.
    private static func rampMask(size: CGSize) -> CGImage? {
        let space = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let colors = [CGColor(red: 0, green: 0, blue: 0, alpha: 1), CGColor(red: 0, green: 0, blue: 0, alpha: 0)] as CFArray
        guard let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) else { return nil }
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size.height), end: .zero, options: [])
        return context.makeImage()
    }
}
