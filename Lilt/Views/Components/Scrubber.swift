import AppKit
import SwiftUI

/// A native `NSSlider` for the playhead. SwiftUI's own slider lets a drag fall through to
/// "move window by background" in a borderless window; a real AppKit control never does.
///
/// The native knob is never drawn. Instead the slider reports its knob's centre and hover state
/// so the caller can float a Liquid Glass knob over the exact spot.
struct Scrubber: NSViewRepresentable {
    @Binding var value: Double
    var range: ClosedRange<Double>
    /// Called with the live value while dragging, and `ended == true` on release.
    var onEditing: (_ value: Double, _ ended: Bool) -> Void
    /// Knob centre x (in the slider's coordinates) and whether the pointer is over the track.
    var onKnob: (_ centerX: CGFloat, _ hovering: Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onEditing: onEditing, onKnob: onKnob) }

    func makeNSView(context: Context) -> HoverSlider {
        let slider = HoverSlider()
        slider.cell = HiddenKnobSliderCell()
        slider.minValue = range.lowerBound
        slider.maxValue = range.upperBound
        slider.doubleValue = value
        slider.target = context.coordinator
        slider.action = #selector(Coordinator.changed(_:))
        slider.controlSize = .mini
        slider.isContinuous = true
        slider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        slider.onKnob = { [weak coordinator = context.coordinator] x, hovering in coordinator?.onKnob(x, hovering) }
        return slider
    }

    func updateNSView(_ slider: HoverSlider, context: Context) {
        context.coordinator.onEditing = onEditing
        context.coordinator.onKnob = onKnob
        slider.minValue = range.lowerBound
        slider.maxValue = range.upperBound
        // Don't fight the user's hand while they're dragging.
        if !context.coordinator.isDragging {
            slider.doubleValue = value
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var onEditing: (Double, Bool) -> Void
        var onKnob: (CGFloat, Bool) -> Void
        private(set) var isDragging = false

        init(onEditing: @escaping (Double, Bool) -> Void, onKnob: @escaping (CGFloat, Bool) -> Void) {
            self.onEditing = onEditing
            self.onKnob = onKnob
        }

        @objc func changed(_ slider: NSSlider) {
            let ended = NSApp.currentEvent?.type == .leftMouseUp
            isDragging = !ended
            onEditing(slider.doubleValue, ended)
        }
    }
}

/// Tracks hover and reports knob position after every draw.
final class HoverSlider: NSSlider {
    var onKnob: ((CGFloat, Bool) -> Void)?
    private(set) var isHovering = false
    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { isHovering = true; report() }
    override func mouseExited(with event: NSEvent) { isHovering = false; report() }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        report()
    }

    fileprivate func report() {
        guard let cell = cell as? NSSliderCell else { return }
        let knob = cell.knobRect(flipped: isFlipped)
        onKnob?(knob.midX, isHovering)
    }
}

/// Draws the track but never the knob; a glass knob floats above it instead.
final class HiddenKnobSliderCell: NSSliderCell {
    override func drawKnob(_ knobRect: NSRect) {}
}
