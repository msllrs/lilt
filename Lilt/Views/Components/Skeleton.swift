import SwiftUI

/// Placeholders shaped like the content they stand in for, so a loading screen keeps the layout
/// it is about to have instead of showing a spinner in the middle of nothing. Tinted from the
/// label colour so they sit on glass and on the sidebar material alike, with a slow shimmer
/// that says "working" (still when Reduce Motion is on).
enum Skeleton {
    static let fill: Color = .primary.opacity(0.07)

    /// A line of text.
    struct Bar: View {
        var width: CGFloat
        var height: CGFloat = 10
        var body: some View {
            RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                .fill(Skeleton.fill)
                .frame(width: width, height: height)
        }
    }

    /// One list row: artwork, title line, subtitle line, laid out exactly like a track or browse
    /// row so the real rows land in place.
    struct Row: View {
        /// Varies the line lengths so a column of rows doesn't read as a grid.
        var seed: Int = 0
        var body: some View {
            HStack(spacing: Theme.Space.md) {
                RoundedRectangle(cornerRadius: Theme.Radius.rowArtwork, style: .continuous)
                    .fill(Skeleton.fill)
                    .frame(width: Theme.Size.rowArtwork, height: Theme.Size.rowArtwork)
                VStack(alignment: .leading, spacing: 7) {
                    Bar(width: [128, 164, 108, 148, 120][seed % 5], height: 11)
                    Bar(width: [72, 56, 88, 64, 80][seed % 5], height: 8)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Space.sm)
            .padding(.vertical, Theme.Space.xs + 2)
        }
    }

    /// A short run of rows, fading out towards the bottom so the list seems to continue rather
    /// than end at a hard edge.
    struct Rows: View {
        var count: Int = 6
        var header: Bool = false
        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                if header {
                    Bar(width: 72, height: 9)
                        .padding(.horizontal, Theme.Space.sm)
                        .padding(.top, Theme.Space.lg)
                        .padding(.bottom, Theme.Space.sm)
                }
                ForEach(0..<count, id: \.self) { i in
                    Row(seed: i)
                        .opacity(1 - Double(i) / Double(max(count, 1)) * 0.6)
                }
            }
            .padding(.horizontal, Theme.Space.rowInset)
            .modifier(Shimmer())
            .accessibilityLabel("Loading")
        }
    }

    /// The Play capsule's footprint under a page's hero.
    struct PlayCapsule: View {
        var body: some View {
            Capsule()
                .fill(Skeleton.fill)
                .frame(width: 92, height: 38)
                .modifier(Shimmer())
        }
    }

    /// A soft band of light passing across the placeholders, once every couple of seconds.
    struct Shimmer: ViewModifier {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var phase: CGFloat = -1

        func body(content: Content) -> some View {
            content
                .overlay {
                    if !reduceMotion {
                        GeometryReader { geometry in
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0),
                                    .init(color: Color.primary.opacity(0.05), location: 0.5),
                                    .init(color: .clear, location: 1),
                                ],
                                startPoint: .leading, endPoint: .trailing
                            )
                            .frame(width: geometry.size.width * 0.6)
                            .offset(x: phase * geometry.size.width)
                        }
                        .mask(content)
                        .allowsHitTesting(false)
                    }
                }
                .onAppear {
                    guard !reduceMotion else { return }
                    withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) { phase = 1.4 }
                }
        }
    }
}
