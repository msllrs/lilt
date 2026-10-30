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
    @Environment(\.screenIsParked) private var parked
    @State private var disc: CGFloat
    /// Angle held when the spin last stopped, and when it resumed.
    @State private var baseAngle: Double = 0
    @State private var resumedAt: Date?

    /// One full turn every eight seconds.
    static let degreesPerSecond: Double = 45

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
        ArtworkView(
            url: url, size: size, radius: radius, context: context,
            spin: ArtworkSpin(baseAngle: baseAngle, resumedAt: resumedAt, degreesPerSecond: Self.degreesPerSecond, paused: !isSpinning || parked)
        )
        // A real hole through the middle, so the background shows like a CD's centre.
        .mask {
            ZStack {
                // Oversized so the ambient shadow spilling past the frame isn't clipped
                // square; only the hole is punched out.
                Rectangle().padding(-size * 2)
                Circle()
                    .frame(width: holeSize * disc, height: holeSize * disc)
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
        }
        .overlay { hub.opacity(disc).scaleEffect(disc) }
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

    private var hubSize: CGFloat { size * 0.36 }
    private var holeSize: CGFloat { size * 0.15 }

    /// The clear plastic hub of a CD: a frosted ring between the hole and the label, with thin
    /// edge lines and a catch of light at the top left.
    private var hub: some View {
        let ringWidth = (hubSize - holeSize) / 2
        return ZStack {
            Circle()
                .strokeBorder(.white.opacity(0.42), lineWidth: ringWidth)
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.55), .white.opacity(0.05), .black.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: ringWidth
                )
            // Outer edge of the hub, and the lip of the hole.
            Circle().stroke(.black.opacity(0.22), lineWidth: 0.5)
            Circle().stroke(.black.opacity(0.3), lineWidth: 0.5)
                .frame(width: holeSize, height: holeSize)
        }
        .frame(width: hubSize, height: hubSize)
    }
}
