import AppKit
import SwiftUI

/// A cover turning as a record, with the turning done by Core Animation. The angle is handed to
/// the render server as one repeating animation, so a spinning disc costs Lilt nothing per
/// frame: SwiftUI hears about the disc only when it starts, stops or changes cover. (Driven by
/// a `TimelineView`, every tick re-ran some 24,000 graph updates and a layout and commit of the
/// whole window, thirty times a second, for as long as music played.)
///
/// Only the picture turns. The sleeve's spotlight, clip, keylines and shadow stay SwiftUI's and
/// sit over or under this view exactly as they did over the SwiftUI image.
struct SpinningPicture: NSViewRepresentable {
    let image: NSImage
    let spin: ArtworkSpin
    var scale: CGFloat = 2

    func makeNSView(context: Context) -> SpinningPictureView {
        let view = SpinningPictureView()
        update(view)
        return view
    }

    func updateNSView(_ view: SpinningPictureView, context: Context) {
        update(view)
    }

    private func update(_ view: SpinningPictureView) {
        view.show(image, scale: scale)
        view.apply(spin)
    }
}

final class SpinningPictureView: NSView {
    /// The cover itself; it turns about the centre of the view.
    let picture = CALayer()
    /// The spin last handed to the layer. A change to anything else (a new cover, the sleeve's
    /// radius) leaves the turning alone.
    private(set) var applied: ArtworkSpin?
    private var image: NSImage?
    private var scale: CGFloat = 2
    /// The angle the picture was last left resting at.
    private var resting: Double = 0

    static let spinKey = "spin"
    /// The turn's frame rate. At 45° a second a 30 Hz frame moves the disc under a degree and a
    /// half, which reads as smooth as 120; left uncapped, a ProMotion display recomposites the
    /// whole panel, its header blur and the platter's glass, at its full rate while music plays.
    static let spinFrameRate = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer = CALayer()
        // The rotated corners and the overflow of a wide cover spill past the bounds, as the
        // SwiftUI image's did; the sleeve's clip shape trims them.
        layer?.masksToBounds = false
        // Left at the default linear filtering, which is what SwiftUI's image uses: a 240px cover
        // shrunk into a 40pt row looks the same either way. (Trilinear softened it.)
        picture.contentsGravity = .resize
        // A bare sublayer animates every property change implicitly; none of these should.
        picture.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull(), "transform": NSNull(), "contentsScale": NSNull()]
        layer?.addSublayer(picture)
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Clicks go to SwiftUI: the disc is the label of a play/pause button.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        placePicture()
    }

    /// A layer leaving the window can lose its animations; coming back, the turn is put back
    /// where the clock says it should be.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, let spin = applied, picture.animation(forKey: Self.spinKey) == nil, spin.isTurning else { return }
        applied = nil
        apply(spin)
    }

    func show(_ image: NSImage, scale: CGFloat) {
        guard image !== self.image || scale != self.scale else { return }
        self.image = image
        self.scale = scale
        picture.contentsScale = image.recommendedLayerContentsScale(scale)
        picture.contents = image.layerContents(forContentsScale: picture.contentsScale)
        placePicture()
    }

    /// Fills the view the way `.aspectRatio(contentMode: .fill)` does, centred.
    private func placePicture() {
        let side = bounds.size
        var fill = side
        if let size = image?.size, size.width > 0, size.height > 0 {
            let ratio = max(side.width / size.width, side.height / size.height)
            fill = CGSize(width: size.width * ratio, height: size.height * ratio)
        }
        picture.bounds = CGRect(origin: .zero, size: fill)
        picture.position = CGPoint(x: bounds.midX, y: bounds.midY)
    }

    /// Puts the picture where `spin` says, now, and keeps it turning if it should. Only a change
    /// of spin touches the layer, so the turn never restarts. A resting angle away from the one
    /// on screen is the disc settling upright, which eases there the shorter way round.
    func apply(_ spin: ArtworkSpin, at now: Date = .now) {
        guard spin != applied else { return }
        let shown = applied.map { shownDegrees(was: $0, at: now) }
        applied = spin
        let degrees = spin.angle(at: now).degrees
        picture.removeAnimation(forKey: Self.spinKey)
        picture.transform = Self.rotation(degrees)
        resting = degrees
        if spin.isTurning {
            let turn = CABasicAnimation(keyPath: "transform.rotation.z")
            // Layers are y-up, so clockwise is a negative turn.
            turn.fromValue = Self.radians(degrees.truncatingRemainder(dividingBy: 360))
            turn.byValue = -2 * Double.pi
            turn.duration = 360 / spin.degreesPerSecond
            turn.repeatCount = .infinity
            turn.isRemovedOnCompletion = false
            turn.preferredFrameRateRange = Self.spinFrameRate
            turn.beginTime = picture.convertTime(CACurrentMediaTime(), from: nil)
            picture.add(turn, forKey: Self.spinKey)
        } else if let shown {
            // The shorter way: start from the angle on screen, wrapped to within half a turn.
            var from = degrees + (shown - degrees).truncatingRemainder(dividingBy: 360)
            if from - degrees > 180 { from -= 360 } else if from - degrees < -180 { from += 360 }
            guard abs(from - degrees) > 1 else { return }
            let curve = Theme.Motion.standardCurve
            // Under Reduce Motion it's upright at once (a keyframe of no duration would run
            // Core Animation's default quarter second instead).
            guard curve.duration > 0 else { return }
            let steps = max(Int(curve.duration * 60), 2)
            let settle = CAKeyframeAnimation(keyPath: "transform.rotation.z")
            settle.values = (0...steps).map { i in
                let progress = curve.value(at: curve.duration * Double(i) / Double(steps))
                return Self.radians(from + (degrees - from) * progress)
            }
            settle.duration = curve.duration
            picture.add(settle, forKey: Self.spinKey)
        }
    }

    /// Where the picture is at `now` under the spin it was last given: by the clock while it
    /// turns, where it was left while it rests, and partway home while it settles.
    private func shownDegrees(was spin: ArtworkSpin, at now: Date) -> Double {
        if picture.animation(forKey: Self.spinKey) is CAKeyframeAnimation { return displayedDegrees }
        return spin.isTurning ? spin.angle(at: now).degrees : resting
    }

    /// The angle on screen, clockwise in degrees from upright, 0..<360.
    var displayedDegrees: Double {
        let layer = picture.presentation() ?? picture
        let radians = (layer.value(forKeyPath: "transform.rotation.z") as? Double) ?? 0
        let degrees = (-radians * 180 / .pi).truncatingRemainder(dividingBy: 360)
        return degrees < 0 ? degrees + 360 : degrees
    }

    private static func radians(_ clockwiseDegrees: Double) -> Double { -clockwiseDegrees * .pi / 180 }

    private static func rotation(_ clockwiseDegrees: Double) -> CATransform3D {
        CATransform3DMakeRotation(radians(clockwiseDegrees), 0, 0, 1)
    }
}
