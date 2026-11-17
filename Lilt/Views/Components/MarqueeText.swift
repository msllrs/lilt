import SwiftUI

/// Single-line text that clips (no ellipsis) under a right-hand fade when it doesn't fit and,
/// when `isActive` (typically on hover), scrolls continuously with both edges faded, snapping
/// back when the hover ends. Text that fits is left alone.
///
/// Until it is first active it is only a line of text, faded at its end when it runs past it:
/// a long list builds one or two of these a row as each row comes in, almost all of them never
/// hovered, and the marquee's clock, measurements and state cost several times the text. Once
/// active it stays a marquee, so a hover that ends runs down as it always did.
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

    /// Set the first time it is active, and kept.
    @State private var isMarquee = false

    var body: some View {
        // The line hands over to the marquee in place, under whatever animation the hover came
        // with: the two draw the same at rest, and a crossfade between them would show.
        lineOrMarquee.animation(nil, value: isActive || isMarquee)
    }

    @ViewBuilder
    private var lineOrMarquee: some View {
        if isActive || isMarquee {
            Marquee(text: text, isActive: isActive, font: font, color: color, speed: speed, gap: gap, delay: delay)
                .onAppear { isMarquee = true }
        } else {
            MarqueeRestingLine(text: text, font: font, color: color)
        }
    }
}

/// A marquee's text at rest: the line itself where it fits, and where it doesn't, clipped (no
/// ellipsis) under the right-hand fade. Draws as the marquee does before it moves.
private struct MarqueeRestingLine: View {
    let text: String
    let font: Font
    let color: AnyShapeStyle

    var body: some View {
        ViewThatFits(in: .horizontal) {
            Text(text).font(font).lineLimit(1)
            // As wide as it's offered, the text at its own width from the leading edge; the
            // fade's bounds clip it.
            Text(text).font(font).fixedSize()
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .mask { Marquee.restingFade }
        }
        .foregroundStyle(color)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The scroll is driven by a clock rather than a repeating animation: the offset is a pure
/// function of elapsed time, so there is no animation state to cancel or go stale. The clock
/// sits as deep as it can, around the offset alone: a tick moves the line and touches nothing
/// else, where a clock around the whole view re-ran its layout sixty times a second.
private struct Marquee: View {
    let text: String
    let isActive: Bool
    let font: Font
    let color: AnyShapeStyle
    let speed: CGFloat
    let gap: CGFloat
    let delay: TimeInterval

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
        #if DEBUG
        let _ = RowBuildCounts.notePart("marquee")
        #endif
        boxOnceMeasured
            .animation(nil, value: isMeasured)
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

    private var isMeasured: Bool { availableWidth > 0 && textHeight > 0 }

    /// Until the first measurement lands the box can't be sized or clipped, so the line stands
    /// in for it, as it looked at rest.
    @ViewBuilder
    private var boxOnceMeasured: some View {
        if isMeasured { box } else { MarqueeRestingLine(text: text, font: font, color: color) }
    }

    private var box: some View {
        // Built here, outside the clock; a tick only moves it.
        let line = HStack(spacing: gap) {
            Text(text).font(font).fixedSize()
            if scrolling { Text(text).font(font).fixedSize() }
        }
        // Laid out as a plain one-line box that takes whatever width it is offered; the text is
        // drawn over it at its natural width and clipped to it. The box never widens its row,
        // and a change of width (the platter growing or shrinking) can't scroll or shift the
        // text the way a scroll view's content offset did.
        return Color.clear
            .overlay(alignment: .leading) {
                TimelineView(.animation(minimumInterval: 1 / 60, paused: !scrolling)) { context in
                    line.offset(x: offset(at: context.date))
                }
                // Clipped to the measured width only, never vertically: a transient height
                // mismatch mid-animation showed as the title cut to a sliver.
                .frame(width: availableWidth, alignment: .leading)
                .clipShape(Rectangle().size(width: availableWidth, height: 1_000).offset(y: -500))
            }
            // The leading fade arrives with the motion, after the delay, not the moment the
            // hover begins.
            .mask { edgeFade(moving: isMoving) }
            .foregroundStyle(color)
            // Exactly one line tall.
            .frame(height: textHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            // The edge fade's bounds and the text move together through a size change.
            .geometryGroup()
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
            Self.restingFade
        } else {
            Color.black
        }
    }

    /// The right-hand fade over text that runs past its end, at rest.
    static var restingFade: LinearGradient {
        LinearGradient(
            stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.88), .init(color: .clear, location: 1)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}
