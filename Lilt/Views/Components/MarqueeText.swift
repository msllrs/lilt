import SwiftUI

/// Single-line text that truncates at rest and, when `isActive` (typically on hover) and too
/// long for its space, scrolls continuously with faded edges, then snaps back when the hover
/// ends. Text that fits is left alone.
struct MarqueeText: View {
    let text: String
    var isActive: Bool
    var font: Font = .body
    var color: AnyShapeStyle = AnyShapeStyle(.primary)
    /// Points per second.
    var speed: CGFloat = 36
    /// Gap between the end of the text and its repeat.
    var gap: CGFloat = 28

    @State private var textWidth: CGFloat = 0
    @State private var availableWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var scrolling = false

    private var overflows: Bool { textWidth > availableWidth + 0.5 }
    private var shouldScroll: Bool { isActive && overflows }

    var body: some View {
        // The label drives layout; it's flexible, so it never widens its row. When the text
        // overflows it is hidden and the untruncated copy shows instead, clipped by the fade:
        // no ellipsis fighting the gradient.
        Text(text)
            .font(font)
            .lineLimit(1)
            .opacity(overflows ? 0 : 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            // The scrolling copy and the measuring copy live in overlay/background, which don't
            // take part in layout, so a long string can't push the row past its container.
            .overlay(alignment: .leading) {
                if overflows {
                    HStack(spacing: gap) {
                        Text(text).font(font).fixedSize()
                        if scrolling { Text(text).font(font).fixedSize() }
                    }
                    .offset(x: offset)
                }
            }
            .background {
                Text(text).font(font).fixedSize().hidden()
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { textWidth = $0 }
            }
            .foregroundStyle(color)
            .clipped()
            .mask { edgeFade }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
            .onChange(of: shouldScroll, initial: true) { _, on in
                on ? start() : stop()
            }
            .onChange(of: text) { _, _ in
                if scrolling { stop(); if shouldScroll { start() } }
            }
    }

    /// Fades the edges only while content runs past them.
    @ViewBuilder
    private var edgeFade: some View {
        if scrolling {
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

    private func start() {
        guard !scrolling, textWidth > 0 else { return }
        scrolling = true
        offset = 0
        let distance = textWidth + gap
        // A beat before moving, so a quick hover doesn't jitter the text.
        withAnimation(.linear(duration: distance / speed).delay(0.6).repeatForever(autoreverses: false)) {
            offset = -distance
        }
    }

    private func stop() {
        withAnimation(nil) {
            scrolling = false
            offset = 0
        }
    }
}
