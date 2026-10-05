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
        /// Gap between the window edge and list rows.
        static let rowInset: CGFloat = 8
        /// Padding inside the now-playing bar.
        static let barPadding: CGFloat = 10
    }

    enum Radius {
        /// The window itself (we draw the shape, so this is ours to choose).
        static let window: CGFloat = 28
        /// Shapes inset by `panelInset`: search field, now-playing bar.
        static let panel: CGFloat = window - Space.panelInset   // 16
        /// Row highlight, inset by `rowInset`.
        static let row: CGFloat = window - Space.rowInset       // 20
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
        /// Transparent margin inside the window frame where the panel's own shadow is drawn.
        /// (The system window shadow is off: it traces every non-transparent pixel and came out
        /// square, so the shadow is drawn in SwiftUI instead.)
        #if NATIVE_FRAME
        /// Native frame: the system draws the shadow, so there is no margin.
        static let shadowMargin: CGFloat = 0
        #else
        static let shadowMargin: CGFloat = 36
        #endif
        /// One row height for every top header (search field, page titles) so switching screens
        /// never shifts the title line or where the list starts.
        static let headerRow: CGFloat = 32
        /// Pictures in a header (account avatar, a page's compact artwork) match the controls they
        /// sit beside, so the header row reads as one line of equal circles.
        static let headerArtwork: CGFloat = headerRow
        static let rowArtwork: CGFloat = 40
        static let barArtwork: CGFloat = 48
        static let controlIcon: CGFloat = 16
        static let playIcon: CGFloat = 22
    }

    enum Motion {
        static let quick: Animation = .easeOut(duration: 0.18)
        static let standard: Animation = .snappy(duration: 0.28)
        /// For a container changing size: `snappy` carries a little bounce, and a frame that
        /// overshoots smaller than its content squeezes the content for a few frames.
        static let settle: Animation = .smooth(duration: 0.3)
        /// A container growing or shrinking with a little overshoot, like the platter revealing
        /// the queue. Content inside must hold its own size (see NowPlayingBar) or it squeezes.
        static let bounce: Animation = .spring(duration: 0.42, bounce: 0.22)
        /// Colour drawn from one cover handing over to the next: slow enough to read as a change
        /// of light, not a cut.
        static let cast: Animation = .easeInOut(duration: 0.8)
        /// The native frame growing or shrinking between the column and the platter: a quick
        /// ease-out with a definite end. (A critically damped spring crept toward its target for
        /// another 0.3s after the visible motion, which read as lag at the end.) The window steps
        /// along this same curve, so the content and the frame land together.
        static let frameDuration: TimeInterval = 0.22
        static let frame: Animation = .easeOut(duration: frameDuration)
        static let frameCurve: FrameCurve = .easeOut(frameDuration)
        /// The platter revealing the queue under the native frame: the window is the platter
        /// and steps along this same spring, so no bounce, or the two overshoot out of phase and
        /// a strip of bare material opens between them.
        static let queueSpring = Spring(duration: 0.3, bounce: 0)
        static let queueCurve: FrameCurve = .spring(queueSpring)
    }
}

/// How the native frame steps between two sizes (see PanelWindow.animateNativeFrame).
enum FrameCurve {
    /// Cubic ease-out over the duration, landing exactly at the end.
    case easeOut(TimeInterval)
    /// A spring, overshoot included, run to its settling time.
    case spring(Spring)

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
            let t = min(max(elapsed / d, 0), 1)
            return 1 - pow(1 - t, 3)
        case .spring(let s):
            return elapsed >= s.settlingDuration ? 1 : s.value(fromValue: 0.0, toValue: 1.0, initialVelocity: 0.0, time: elapsed)
        }
    }
}
