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
        static let rowArtwork: CGFloat = 40
        static let barArtwork: CGFloat = 48
        static let controlIcon: CGFloat = 16
        static let playIcon: CGFloat = 22
    }

    enum Motion {
        static let quick: Animation = .easeOut(duration: 0.18)
        static let standard: Animation = .snappy(duration: 0.28)
    }
}
