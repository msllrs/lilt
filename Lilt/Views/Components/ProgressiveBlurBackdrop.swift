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
    private var lastKey: String?

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

    override func layout() {
        super.layout()
        backdrop?.frame = bounds
        fade.frame = bounds
    }

    func configure(radius: Double, saturation: Double, brightness: Double, fadeStart: Double) {
        guard let backdrop else { return }
        let key = "\(radius)|\(saturation)|\(brightness)|\(fadeStart)"
        guard key != lastKey else { return }
        lastKey = key
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        var filters: [Any] = []
        if let blur = ProgressiveBlurBackdrop.makeFilter("variableBlur") {
            blur.setValue(radius, forKey: "inputRadius")
            blur.setValue(Self.rampMask, forKey: "inputMaskImage")
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
        backdrop.filters = filters
        // The whole effect fades out below `fadeStart`, so rows melt into it instead of meeting
        // a hard line where the blur stops.
        fade.colors = [NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
        fade.locations = [0, NSNumber(value: fadeStart), 1]
        CATransaction.commit()
    }

    /// The variable blur's mask: white (full radius) at the top, black (none) at the bottom. One
    /// pixel wide; the filter stretches it over the layer.
    private static let rampMask: CGImage = {
        let height = 64
        let space = CGColorSpaceCreateDeviceGray()
        let context = CGContext(data: nil, width: 1, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        let gradient = CGGradient(colorsSpace: space, colors: [CGColor(gray: 1, alpha: 1), CGColor(gray: 0, alpha: 1)] as CFArray, locations: [0, 1])!
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: CGFloat(height)), end: .zero, options: [])
        return context.makeImage()!
    }()
}
