import SwiftUI

/// Artwork that can become a record: corners round off to a circle, a spindle hole appears, and
/// the picture spins while `isSpinning`, holding its angle when paused and settling back upright
/// when `isDisc` turns off. Used by track rows and the collapsed page header.
struct SpinningArtwork: View {
    let url: URL?
    let size: CGFloat
    /// Corner radius when not a disc.
    let restRadius: CGFloat
    var context: ArtworkContext = .row
    let isDisc: Bool
    let isSpinning: Bool

    /// 0 = ordinary artwork, 1 = disc. Animated explicitly.
    @State private var disc: CGFloat
    /// Angle held when the spin last stopped, and when it resumed.
    @State private var baseAngle: Double = 0
    @State private var resumedAt: Date?

    /// One full turn every eight seconds.
    private static let degreesPerSecond: Double = 45

    init(url: URL?, size: CGFloat, restRadius: CGFloat, context: ArtworkContext = .row, isDisc: Bool, isSpinning: Bool) {
        self.url = url
        self.size = size
        self.restRadius = restRadius
        self.context = context
        self.isDisc = isDisc
        self.isSpinning = isSpinning
        _disc = State(initialValue: isDisc ? 1 : 0)
        // A view that mounts already spinning must start its clock straight away.
        _resumedAt = State(initialValue: isSpinning ? .now : nil)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !isSpinning)) { context in
            let elapsed = resumedAt.map { context.date.timeIntervalSince($0) } ?? 0
            let angle = baseAngle + (isSpinning ? elapsed * Self.degreesPerSecond : 0)
            ArtworkView(url: url, size: size, radius: radius, context: self.context, rotation: .degrees(angle))
                .overlay { spindleHole.opacity(disc).scaleEffect(disc) }
        }
        .onChange(of: isSpinning) { _, spinning in
            if spinning {
                resumedAt = .now
            } else if let resumedAt {
                baseAngle = (baseAngle + Date.now.timeIntervalSince(resumedAt) * Self.degreesPerSecond)
                    .truncatingRemainder(dividingBy: 360)
                self.resumedAt = nil
            }
        }
        .onChange(of: isDisc) { _, on in
            withAnimation(Theme.Motion.standard) {
                disc = on ? 1 : 0
                // Back to artwork: settle upright by the shorter way round.
                if !on { baseAngle = baseAngle > 180 ? 360 : 0 }
            }
            if !on { resumedAt = nil }
        }
    }

    private var radius: CGFloat { restRadius + (size / 2 - restRadius) * disc }

    /// The hole in the middle of the record, scaled to the artwork.
    private var spindleHole: some View {
        Circle()
            .fill(.black.opacity(0.75))
            .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 0.5))
            .frame(width: size * 0.175, height: size * 0.175)
    }
}
