import AppKit
import SwiftUI

/// A native `NSSlider` for the playhead, drawn as a bare progress line with no knob: click to
/// jump, drag to scrub. SwiftUI's own slider lets a drag fall through to "move window by
/// background" in a borderless window; a real AppKit control never does.
struct Scrubber: NSViewRepresentable {
    @Binding var value: Double
    var range: ClosedRange<Double>
    /// Called with the live value while dragging, and `ended == true` on release.
    var onEditing: (_ value: Double, _ ended: Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onEditing: onEditing) }

    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider()
        slider.cell = LineSliderCell()
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

    func updateNSView(_ slider: NSSlider, context: Context) {
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
            onEditing(slider.doubleValue, ended)
        }
    }
}

/// A neutral track with no knob. Elapsed is the label colour, so black in light mode and
/// white in dark, over a faint rail in the same colour.
final class LineSliderCell: NSSliderCell {
    override func drawKnob(_ knobRect: NSRect) {}

    override func drawBar(inside rect: NSRect, flipped: Bool) {
        let height: CGFloat = 5
        let rail = NSRect(x: rect.minX, y: rect.midY - height / 2, width: rect.width, height: height)
        NSColor.labelColor.withAlphaComponent(0.15).setFill()
        NSBezierPath(roundedRect: rail, xRadius: height / 2, yRadius: height / 2).fill()

        let knobX = knobRect(flipped: flipped).midX
        let elapsed = NSRect(x: rail.minX, y: rail.minY, width: max(knobX - rail.minX, height), height: height)
        NSColor.labelColor.setFill()
        NSBezierPath(roundedRect: elapsed, xRadius: height / 2, yRadius: height / 2).fill()
    }
}
