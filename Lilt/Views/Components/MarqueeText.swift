import SwiftUI

/// Single-line text that clips (no ellipsis) under a right-hand fade when it doesn't fit and,
/// when `isActive` (typically on hover), scrolls continuously with both edges faded, snapping
/// back when the hover ends. Text that fits is left alone.
///
/// The scroll is driven by a clock rather than a repeating animation: the offset is a pure
/// function of elapsed time, so there is no animation state to cancel or go stale. The clock
/// sits as deep as it can, around the offset alone: a tick moves the line and touches nothing
/// else, where a clock around the whole view re-ran its layout sixty times a second.
struct MarqueeText: View {
    let text: String
    var isActive: Bool
    var font: Font = .body
    var color: AnyShapeStyle = AnyShapeStyle(.primary)
    /// Points per second.
    var speed: CGFloat = 36
    /// Gap between the end of the text and its repeat.
    var gap: CGFloat = 28
    /// Pause before moving, so a quick hover doesn't jitter the text.
    var delay: TimeInterval = 0.6

    @State private var textWidth: CGFloat = 0
    @State private var textHeight: CGFloat = 0
    @State private var availableWidth: CGFloat = 0
    @State private var scrollStart: Date?
    /// True once the delay has passed and the text is moving; the leading fade arrives with it.
    @State private var isMoving = false
    @State private var movingTask: Task<Void, Never>?

    private var overflows: Bool { textWidth > availableWidth + 0.5 }
    @Environment(\.screenIsParked) private var parked
    private var shouldScroll: Bool { isActive && overflows && !parked }
    private var scrolling: Bool { scrollStart != nil }

    var body: some View {
        // Built here, outside the clock; a tick only moves it.
        let line = HStack(spacing: gap) {
            Text(text).font(font).fixedSize()
            if scrolling { Text(text).font(font).fixedSize() }
        }
        // Laid out as a plain one-line box that takes whatever width it is offered; the text is
        // drawn over it at its natural width and clipped to it. The box never widens its row,
        // and a change of width (the platter growing or shrinking) can't scroll or shift the
        // text the way a scroll view's content offset did.
        Color.clear
            .overlay(alignment: .leading) {
                TimelineView(.animation(minimumInterval: 1 / 60, paused: !scrolling)) { context in
                    line.offset(x: offset(at: context.date))
                }
                // Clipped to the measured width only: never vertically (a transient height
                // mismatch mid-animation showed as the title cut to a sliver), and not at all
                // before the first measurement.
                .frame(width: availableWidth > 0 ? availableWidth : nil, alignment: .leading)
                .clipShape(Rectangle().size(width: availableWidth > 0 ? availableWidth : 10_000, height: 1_000).offset(y: -500))
            }
            // The leading fade arrives with the motion, after the delay, not the moment the
            // hover begins.
            .mask { edgeFade(moving: isMoving) }
            .foregroundStyle(color)
            // Exactly one line tall.
            .frame(height: textHeight > 0 ? textHeight : nil)
            .frame(maxWidth: .infinity, alignment: .leading)
            // The edge fade's bounds and the text move together through a size change.
            .geometryGroup()
            .background {
                // Measures the natural size without taking part in layout.
                Text(text).font(font).fixedSize().hidden()
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { textWidth = $0.width; textHeight = $0.height }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
            .onChange(of: shouldScroll, initial: true) { _, on in
                scrollStart = on ? .now : nil
                scheduleMoving()
            }
            .onChange(of: text) { _, _ in
                scrollStart = shouldScroll ? .now : nil
                scheduleMoving()
            }
    }

    /// Flags the text as moving once the delay has passed, so the fade follows without the
    /// clock having to be asked on every tick.
    private func scheduleMoving() {
        movingTask?.cancel()
        isMoving = false
        guard scrollStart != nil else { return }
        movingTask = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            isMoving = true
        }
    }

    private func offset(at date: Date) -> CGFloat {
        guard let start = scrollStart, textWidth > 0 else { return 0 }
        let travelled = max(0, date.timeIntervalSince(start) - delay) * speed
        let distance = textWidth + gap
        return -CGFloat(travelled).truncatingRemainder(dividingBy: distance)
    }

    /// Fades the edges only while content runs past them.
    @ViewBuilder
    private func edgeFade(moving: Bool) -> some View {
        if moving {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.08),
                    .init(color: .black, location: 0.92),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        } else if overflows {
            LinearGradient(
                stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.88), .init(color: .clear, location: 1)],
                startPoint: .leading,
                endPoint: .trailing
            )
        } else {
            Color.black
        }
    }
}
