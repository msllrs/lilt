import SwiftUI

/// Design tokens. Every spacing, radius and size in the UI comes from here.
///
/// Radii are concentric: a shape inset by `d` inside another shape of radius `r` gets radius
/// `r - d`, so corners share a centre instead of fighting each other.
enum Theme {
    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24

        /// Gap between the window edge and the first content shape (search field, bar).
        static let panelInset: CGFloat = 12
        /// Gap between the window edge and list rows. With `rowPadding` it puts a row's cover
        /// 16pt from the window edge.
        static let rowInset: CGFloat = 10
        /// Padding inside a list row, the same on every side so its highlight is concentric with
        /// the cover.
        static let rowPadding: CGFloat = xs + 2
        /// Padding inside the now-playing bar.
        static let barPadding: CGFloat = 10
    }

    enum Radius {
        /// The window itself (we draw the shape, so this is ours to choose).
        static let window: CGFloat = 28
        /// Shapes inset by `panelInset`: search field, now-playing bar.
        static let panel: CGFloat = window - Space.panelInset   // 16
        /// Row highlight, inset by `rowInset`.
        static let row: CGFloat = window - Space.rowInset       // 18
        /// Artwork is a sleeve, not a nested panel: it keeps one proportional roundness wherever
        /// it appears instead of inheriting its container's corner.
        static func artwork(_ size: CGFloat) -> CGFloat { (size * 0.2).rounded() }
        static let rowArtwork: CGFloat = artwork(Size.rowArtwork)   // 8
        static let barArtwork: CGFloat = artwork(Size.barArtwork)   // 10
        /// Free-standing shapes not nested in anything.
        static let standalone: CGFloat = 16
    }

    enum Size {
        /// Default panel width when first placed on the screen edge.
        static let panelWidth: CGFloat = 320
        static let panelMinWidth: CGFloat = 280
        static let panelMaxWidth: CGFloat = 420
        static let panelMinHeight: CGFloat = 480
        /// Gap between the panel and the screen edges.
        static let screenInset: CGFloat = 12
        /// One row height for every top header (search field, page titles) so switching screens
        /// never shifts the title line or where the list starts.
        static let headerRow: CGFloat = 32
        /// Pictures in a header (account avatar, a page's compact artwork) match the controls they
        /// sit beside, so the header row reads as one line of equal circles.
        static let headerArtwork: CGFloat = headerRow
        static let rowArtwork: CGFloat = 40
        /// Every list row (track, album, artist, playlist): the artwork plus its vertical padding.
        static let row: CGFloat = rowArtwork + Space.rowPadding * 2
        static let barArtwork: CGFloat = 48
        static let controlIcon: CGFloat = 16
        static let playIcon: CGFloat = 22
        /// A notice's cover or symbol, and its button's height.
        static let noticeArtwork: CGFloat = 24
        /// Settings ▸ Appearance draws each window style as the panel in miniature: the panel's
        /// own layout and tokens at this fraction of their size (a 320 × 480 panel is 64 × 96).
        static let windowStylePreviewScale: CGFloat = 0.2
        /// The ring round the chosen window style, in the system accent colour.
        static let selectionRing: CGFloat = 2
    }

    /// Every duration here is the designed one stretched to the current `MotionPace`, so the
    /// tweak panel's Animation speed slows them all alike; at 1× each token is exactly its
    /// designed curve.
    ///
    /// Each token also says what it becomes under Reduce Motion. Travel (a page sliding, the
    /// window or the platter changing size, rows shuffling, a disc turning upright) lands at once,
    /// or keeps only its fade; fades, colour and small in-place changes stay as they are.
    enum Motion {
        private static func scaled(_ seconds: TimeInterval) -> TimeInterval { MotionPace.current.scaled(seconds) }
        static var reducesMotion: Bool { MotionPace.current.reducesMotion }
        /// Reduce Motion: no animation, the change lands at once.
        private static func instantIfReduced(_ animation: Animation) -> Animation? { reducesMotion ? nil : animation }

        /// Reduce Motion: kept, a short fade.
        static var quick: Animation { .easeOut(duration: scaled(0.18)) }
        /// Reduce Motion: kept; content swapping in place and the disc's morph.
        static var standard: Animation { .snappy(duration: scaled(0.28)) }
        /// `standard` for motion SwiftUI doesn't drive, like a Core Animation layer settling: the
        /// disc easing upright. Reduce Motion: instant, it's upright at once.
        static var standardCurve: FrameCurve { reducesMotion ? .instant : .spring(.snappy(duration: scaled(0.28))) }
        /// For a container changing size: `snappy` carries a little bounce, and a frame that
        /// overshoots smaller than its content squeezes the content for a few frames. Up Next's
        /// rows shuffling up and the list resizing. Reduce Motion: instant, the window it sits in
        /// snaps too.
        static var settle: Animation? { instantIfReduced(.smooth(duration: scaled(0.3))) }
        /// A container growing or shrinking with a little overshoot, like the platter revealing
        /// the queue. Content inside must hold its own size (see NowPlayingBar) or it squeezes.
        /// Reduce Motion: instant.
        static var bounce: Animation? { instantIfReduced(.spring(duration: scaled(0.42), bounce: 0.22)) }
        /// Colour drawn from one cover handing over to the next: slow enough to read as a change
        /// of light, not a cut. Reduce Motion: kept, nothing moves.
        static var cast: Animation { .easeInOut(duration: scaled(0.8)) }
        /// The native frame growing or shrinking between the column and the platter: a quick
        /// ease-out with a definite end. (A critically damped spring crept toward its target for
        /// another 0.3s after the visible motion, which read as lag at the end.) The window steps
        /// along this same curve, so the content and the frame land together.
        /// Reduce Motion: the frame snaps, and the content with it. A window edge can't
        /// crossfade, and a shorter ease only sweeps the same distance faster.
        static var frameDuration: TimeInterval { reducesMotion ? 0 : scaled(0.22) }
        static var frame: Animation? { instantIfReduced(.easeOut(duration: frameDuration)) }
        static var frameCurve: FrameCurve { .easeOut(frameDuration) }
        /// The platter revealing the queue under the native frame: the window is the platter
        /// and steps along this same spring, so no bounce, or the two overshoot out of phase and
        /// a strip of bare material opens between them. Reduce Motion: the list and the window
        /// land at once, opened, closed, or let go after a pull.
        static var queueSpring: Spring { Spring(duration: scaled(0.3), bounce: 0) }
        static var queue: Animation? { instantIfReduced(.spring(queueSpring)) }
        static var queueCurve: FrameCurve { reducesMotion ? .instant : .spring(queueSpring) }
        /// A page arriving on the navigation stack, and the one beneath getting out of its way:
        /// faster, so the two never read as a double exposure on the glass. Reduce Motion: kept,
        /// with no `pageTravel` the hand-off is a crossfade.
        static var pageEnter: Animation { .easeOut(duration: scaled(0.2)) }
        static var pageExit: Animation { .easeOut(duration: scaled(0.12)) }
        /// How far a page slides while entering or leaving. Reduce Motion: none.
        static var pageTravel: CGFloat { reducesMotion ? 0 : 20 }
        /// One glyph handing over to another in place (play ↔ pause, library ↔ back).
        /// Reduce Motion: kept, it doesn't travel.
        static var symbol: Animation { .snappy(duration: scaled(0.22)) }
        /// A pressable button giving under the cursor, and springing back when let go.
        /// Reduce Motion: kept, a few percent of scale under the pointer.
        static var press: Animation { .easeOut(duration: scaled(0.08)) }
        static var release: Animation { .spring(duration: scaled(0.3), bounce: 0.35) }
        /// A control's hop to confirm itself (see `AttentionStyle`), from the tweak panel's
        /// dials. Reduce Motion: no hop, nothing moves or grows; a short dip in opacity.
        static func attention(_ style: AttentionStyle) -> Attention {
            if reducesMotion { return .pulse(duration: scaled(style.pulse), opacity: style.pulseOpacity) }
            return .hop(
                rise: scaled(style.rise),
                settle: Spring(response: scaled(style.response), dampingRatio: style.damping),
                jump: style.jump,
                scale: style.scale
            )
        }

        enum Attention: Equatable {
            /// Up by `jump` and to `scale` over `rise` seconds, then back on `settle`.
            case hop(rise: TimeInterval, settle: Spring, jump: Double, scale: Double)
            /// Down to `opacity` and back, `duration` each way.
            case pulse(duration: TimeInterval, opacity: Double)
        }
    }
}

/// How the native frame steps between two sizes (see PanelWindow.animateNativeFrame).
enum FrameCurve {
    /// Cubic ease-out over the duration, landing exactly at the end.
    case easeOut(TimeInterval)
    /// A spring, overshoot included, run to its settling time.
    case spring(Spring)

    /// No time at all: the frame lands where it's going.
    static let instant = FrameCurve.easeOut(0)

    var duration: TimeInterval {
        switch self {
        case .easeOut(let d): d
        case .spring(let s): s.settlingDuration
        }
    }

    /// Progress 0...1 (springs may exceed 1 briefly) at `elapsed` seconds.
    func value(at elapsed: TimeInterval) -> Double {
        switch self {
        case .easeOut(let d):
            guard d > 0 else { return 1 }
            let t = min(max(elapsed / d, 0), 1)
            return 1 - pow(1 - t, 3)
        case .spring(let s):
            return elapsed >= s.settlingDuration ? 1 : s.value(fromValue: 0.0, toValue: 1.0, initialVelocity: 0.0, time: elapsed)
        }
    }
}
