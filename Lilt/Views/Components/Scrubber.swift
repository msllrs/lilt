import AppKit
import SwiftUI

/// A native `NSSlider` for the playhead. SwiftUI's own slider lets a drag fall through to
/// "move window by background" in a borderless window; a real AppKit control never does.
struct Scrubber: NSViewRepresentable {
    @Binding var value: Double
    var range: ClosedRange<Double>
    /// Called with the live value while dragging, and `ended == true` on release.
    var onEditing: (_ value: Double, _ ended: Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onEditing: onEditing) }

    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider(value: value, minValue: range.lowerBound, maxValue: range.upperBound,
                              target: context.coordinator, action: #selector(Coordinator.changed(_:)))
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
