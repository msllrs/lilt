import AppKit
import ObjectiveC
import QuartzCore
import SwiftUI

/// The blur a page transition passes through, laid over the staged stack rather than put on a
/// page. A blur on the page itself is a filter over a live scroll view and every row in it:
/// Core Animation renders the whole page apart to blur it, and the frame that first does so held
/// the fade back by about a tenth of a second (twice per move, once for each page). This is one
/// backdrop layer above the pages, blurring whatever they draw beneath it, as the header's own
/// blur does, and only while a move runs: hidden the rest of the time, so a page at rest costs
/// nothing.
///
/// Its radius follows the pages' fades (`PageChoreography.veil(at:for:)`): none while the page
/// leaving is fully there, the most as the two hand over, none again once the page arriving has
/// settled. Played by Core Animation as one keyframe animation per move, so no frame of it is
/// drawn by SwiftUI. Private classes (`CABackdropLayer`, `CAFilter`), gated like
/// `ProgressiveBlurBackdrop`; without them the move simply has no blur.
struct BlurVeil: NSViewRepresentable {
    /// The stack's screens, root first, by id: a change is a move.
    let path: [String]
    let choreography: PageChoreography

    func makeNSView(context: Context) -> VeilView { VeilView(path: path) }

    func updateNSView(_ view: VeilView, context: Context) {
        view.update(path: path, choreography: choreography)
    }
}

final class VeilView: NSView {
    private var backdrop: CALayer?
    private var path: [String]
    /// Counts moves, so a move cut short by the next one doesn't hide the veil mid-way.
    private var moves = 0

    init(path: [String]) {
        self.path = path
        super.init(frame: .zero)
        wantsLayer = true
        guard let type = NSClassFromString("CABackdropLayer") as? CALayer.Type, let blur = Self.blur(radius: 0) else { return }
        let layer = type.init()
        // Half resolution, as the system's materials blur; plenty for a blur this brief.
        if layer.responds(to: NSSelectorFromString("setScale:")) { layer.setValue(0.5, forKey: "scale") }
        // Lilt's own layers only (the pages), never the desktop behind the panel. A BOOL,
        // checked before the write (see ProgressiveBlurBackdrop).
        if let property = class_getProperty(type, "windowServerAware"), let attributes = property_getAttributes(property),
           String(cString: attributes).hasPrefix("TB") {
            layer.setValue(false, forKey: "windowServerAware")
        }
        layer.filters = [blur]
        layer.isHidden = true
        self.layer?.addSublayer(layer)
        backdrop = layer
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backdrop?.frame = bounds
        CATransaction.commit()
    }

    private static func blur(radius: CGFloat) -> NSObject? {
        guard let cls = NSClassFromString("CAFilter") as? NSObject.Type else { return nil }
        let selector = NSSelectorFromString("filterWithType:")
        guard cls.responds(to: selector), let filter = cls.perform(selector, with: "gaussianBlur")?.takeUnretainedValue() as? NSObject else { return nil }
        filter.setValue("veil", forKey: "name")
        filter.setValue(radius, forKey: "inputRadius")
        filter.setValue(true, forKey: "inputNormalizeEdges")
        return filter
    }

    /// The stack is now `new`: if that is a move and the variant blurs, play this move's blur.
    func update(path new: [String], choreography: PageChoreography) {
        let move = PageMove.between(path, new)
        path = new
        guard let backdrop, move != .none, choreography.veilBlur > 0 else { return }
        let duration = max(choreography.longest, 0.0001)
        let steps = 48
        let values = (0...steps).map { choreography.veil(at: duration * Double($0) / Double(steps), for: move) }
        moves += 1
        let count = moves
        let animation = CAKeyframeAnimation(keyPath: "filters.veil.inputRadius")
        animation.values = values
        animation.keyTimes = (0...steps).map { NSNumber(value: Double($0) / Double(steps)) }
        animation.calculationMode = .linear
        animation.duration = duration
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backdrop.isHidden = false
        CATransaction.setCompletionBlock { [weak self] in
            guard let self, self.moves == count else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.backdrop?.isHidden = true
            CATransaction.commit()
        }
        backdrop.removeAnimation(forKey: "veil")
        backdrop.add(animation, forKey: "veil")
        CATransaction.commit()
    }
}
