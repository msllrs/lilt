import AppKit
import ObjectiveC
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
    /// Upside down: full blur at the bottom edge, fading upward (for the bottom of a list).
    var flipped: Bool = false
    /// Radius of the panel corners on the edge the effect sits against, so the layer is clipped
    /// to the panel shape itself rather than trusting a clip further up the view tree.
    var cornerRadius: CGFloat = Theme.Radius.window
    /// Render in-process from the layers beneath, so nothing behind the window is sampled.
    var ownContentOnly: Bool = true

    /// True when the private classes exist and accept the filter we need.
    static let isAvailable: Bool = {
        guard NSClassFromString("CABackdropLayer") is CALayer.Type else { return false }
        return makeFilter("variableBlur") != nil
    }()

    func makeNSView(context: Context) -> BackdropHostView { BackdropHostView() }

    func updateNSView(_ view: BackdropHostView, context: Context) {
        view.rampFlipped = flipped
        view.cornerRadius = cornerRadius
        view.ownContentOnly = ownContentOnly
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
    /// Holds the backdrop so the panel-shaped clip and the fade can both apply (a mask can't
    /// carry a mask of its own).
    private let container = CALayer()
    private let clip = CAShapeLayer()
    private var blur: NSObject?
    private var radius = 0.0, saturation = 1.0, brightness = 0.0
    private var maskSize = CGSize.zero

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        fade.startPoint = CGPoint(x: 0.5, y: 1)
        fade.endPoint = CGPoint(x: 0.5, y: 0)
        container.mask = clip
        self.layer?.addSublayer(container)
        makeBackdrop()
    }

    /// The backdrop layer, built for the current scope. Core Animation settles which renderer a
    /// backdrop uses when the layer is set up, so a change of scope replaces the layer rather
    /// than flipping the flag on the one in place.
    private func makeBackdrop() {
        guard let type = NSClassFromString("CABackdropLayer") as? CALayer.Type else { return }
        backdrop?.removeFromSuperlayer()
        let layer = type.init()
        // The blur never needs full resolution; half is what the system uses for its materials.
        if layer.responds(to: NSSelectorFromString("setScale:")) { layer.setValue(0.5, forKey: "scale") }
        // `windowServerAware` is the private switch between the two renderers; a BOOL, checked
        // before the write since a wrong type through KVC raises and takes the app down.
        if Self.isBoolProperty("windowServerAware", of: layer) { layer.setValue(!ownContentOnly, forKey: "windowServerAware") }
        layer.mask = fade
        container.addSublayer(layer)
        backdrop = layer
        maskSize = .zero
        needsLayout = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { false }

    /// The layer covers the view and no more. A backdrop blurs whatever lies under its own
    /// bounds, which past the window's edge is the desktop beside the panel: a layer run past
    /// the view (once, to hide edge pixels that never blurred fully) pulled that desktop in, and
    /// a dark one showed as dark bands down the panel's sides and across its top. With edge
    /// normalisation the blur reaches right to the layer's edge from what is inside it alone.
    /// The clip below rounds the panel's corners, which a behind-window backdrop ignores the
    /// window's own clip for.
    var cornerRadius: CGFloat = Theme.Radius.window {
        didSet { if cornerRadius != oldValue { needsLayout = true } }
    }
    private var fadeStart: CGFloat = 1
    /// Whether the window server composites the backdrop (and so samples the windows behind
    /// this non-opaque panel too) or the layer is rendered here from Lilt's own content only.
    var ownContentOnly = true {
        didSet { if ownContentOnly != oldValue { makeBackdrop() } }
    }

    private static func isBoolProperty(_ name: String, of object: NSObject) -> Bool {
        guard let property = class_getProperty(type(of: object), name),
              let attributes = property_getAttributes(property) else { return false }
        return String(cString: attributes).hasPrefix("TB")
    }

    /// Full blur at the bottom edge instead of the top (NSView already has `isFlipped`).
    var rampFlipped = false {
        didSet { if rampFlipped != oldValue { maskSize = .zero; needsLayout = true } }
    }

    override func layout() {
        super.layout()
        container.frame = bounds
        backdrop?.frame = container.bounds
        fade.frame = container.bounds
        clip.frame = container.bounds
        // The panel's corners on the edge the effect sits against (layer coordinates: y up, so
        // the top corners are the max-y ones).
        let viewRect = container.bounds
        let r = cornerRadius
        if r > 0 {
            let shape = UnevenRoundedRectangle(
                topLeadingRadius: rampFlipped ? r : 0, bottomLeadingRadius: rampFlipped ? 0 : r,
                bottomTrailingRadius: rampFlipped ? 0 : r, topTrailingRadius: rampFlipped ? r : 0,
                style: .continuous
            )
            clip.path = shape.path(in: viewRect).cgPath
        } else {
            // No shape of ours: the whole layer stays and the window clips it.
            clip.path = CGPath(rect: container.bounds, transform: nil)
        }
        fade.startPoint = CGPoint(x: 0.5, y: rampFlipped ? 0 : 1)
        fade.endPoint = CGPoint(x: 0.5, y: rampFlipped ? 1 : 0)
        applyFade()
        applyFilters()
    }

    /// The fade's locations are fractions of the layer, which is the view, so the caller's
    /// fraction is used as it is.
    private func applyFade() {
        guard bounds.height > 0 else { return }
        let start = fadeStart
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
        if let blur = ProgressiveBlurBackdrop.makeFilter("variableBlur"), let mask = Self.rampMask(size: size, flipped: rampFlipped) {
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
    private static func rampMask(size: CGSize, flipped: Bool) -> CGImage? {
        let space = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let colors = [CGColor(red: 0, green: 0, blue: 0, alpha: 1), CGColor(red: 0, green: 0, blue: 0, alpha: 0)] as CFArray
        guard let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) else { return nil }
        let top = CGPoint(x: 0, y: size.height)
        context.drawLinearGradient(gradient, start: flipped ? .zero : top, end: flipped ? top : .zero, options: [])
        return context.makeImage()
    }
}
