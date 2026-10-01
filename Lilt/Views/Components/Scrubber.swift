import AppKit
import SwiftUI

/// A native `NSSlider` for the playhead. SwiftUI's own slider lets a drag fall through to
/// "move window by background" in a borderless window; a real AppKit control never does.
/// The knob only appears while hovering or dragging, so at rest it reads as a progress line.
struct Scrubber: NSViewRepresentable {
    @Binding var value: Double
    var range: ClosedRange<Double>
    /// Called with the live value while dragging, and `ended == true` on release.
    var onEditing: (_ value: Double, _ ended: Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onEditing: onEditing) }

    func makeNSView(context: Context) -> HoverSlider {
        let slider = HoverSlider()
        slider.cell = HoverSliderCell()
        slider.minValue = range.lowerBound
        slider.maxValue = range.upperBound
        slider.doubleValue = value
        slider.target = context.coordinator
        slider.action = #selector(Coordinator.changed(_:))
        slider.controlSize = .mini
        slider.isContinuous = true
        slider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return slider
    }

    func updateNSView(_ slider: HoverSlider, context: Context) {
        context.coordinator.onEditing = onEditing
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
        private(set) var isDragging = false

        init(onEditing: @escaping (Double, Bool) -> Void) { self.onEditing = onEditing }

        @objc func changed(_ slider: NSSlider) {
            let ended = NSApp.currentEvent?.type == .leftMouseUp
            isDragging = !ended
            (slider as? HoverSlider)?.isDragging = !ended
            onEditing(slider.doubleValue, ended)
        }
    }
}

/// Tracks hover so the cell knows when to draw its knob.
final class HoverSlider: NSSlider {
    var isHovering = false { didSet { needsDisplay = true } }
    var isDragging = false { didSet { needsDisplay = true } }
    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { isHovering = true }
    override func mouseExited(with event: NSEvent) { isHovering = false }
}

final class HoverSliderCell: NSSliderCell {
    override func drawKnob(_ knobRect: NSRect) {
        guard let slider = controlView as? HoverSlider, slider.isHovering || slider.isDragging else { return }
        super.drawKnob(knobRect)
    }
}
