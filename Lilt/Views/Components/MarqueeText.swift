import SwiftUI

/// Single-line text that clips (no ellipsis) under a right-hand fade when it doesn't fit and,
/// when `isActive` (typically on hover), scrolls continuously with both edges faded, snapping
/// back when the hover ends. Text that fits is left alone.
///
/// The scroll is driven by a clock rather than a repeating animation: the offset is a pure
/// function of elapsed time, so there is no animation state to cancel or go stale.
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

    private var overflows: Bool { textWidth > availableWidth + 0.5 }
    private var shouldScroll: Bool { isActive && overflows }
    private var scrolling: Bool { scrollStart != nil }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: !scrolling)) { context in
            // A disabled horizontal scroll view is the one container that is flexible in layout
            // (so it never widens its row), clips its content, and shows text without an ellipsis.
            ScrollView(.horizontal) {
                HStack(spacing: gap) {
                    Text(text).font(font).fixedSize()
                    if scrolling { Text(text).font(font).fixedSize() }
                }
                .offset(x: offset(at: context.date))
            }
            .scrollDisabled(true)
            .scrollIndicators(.hidden)
            // The leading fade arrives with the motion, after the delay, not the moment the
            // hover begins.
            .mask { edgeFade(moving: isMoving(at: context.date)) }
        }
        .foregroundStyle(color)
        // Exactly one line tall. A scroll view would happily shrink to nothing when its
        // container is squeezed, taking the title with it.
        .frame(height: textHeight > 0 ? textHeight : nil)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            // Measures the natural size without taking part in layout.
            Text(text).font(font).fixedSize().hidden()
                .onGeometryChange(for: CGSize.self) { $0.size } action: { textWidth = $0.width; textHeight = $0.height }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
        .onChange(of: shouldScroll, initial: true) { _, on in
            scrollStart = on ? .now : nil
        }
        .onChange(of: text) { _, _ in
            scrollStart = shouldScroll ? .now : nil
        }
    }

    /// Whether the text has started to move (the hover delay has passed).
    private func isMoving(at date: Date) -> Bool {
        guard let start = scrollStart else { return false }
        return date.timeIntervalSince(start) >= delay
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
