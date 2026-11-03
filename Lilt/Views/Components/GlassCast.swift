import SwiftUI

/// The cover's colour cast onto a glass control, the palette's accent container: a wash falling
/// off from the lit edge across the control and a rim catching the light along that edge,
/// composited the palette's way (added as light on dark glass). The album hero's controls are
/// lit from the top, by the cover above them; the compact header's back button from its
/// trailing side, by the header beside it, and is revealed as the header rises (`reveal`): the
/// wash fades in and the rim climbs the edge, bottom to top. Draws nothing when the palette
/// casts nothing.
struct GlassCast<S: InsettableShape>: View {
    let shape: S
    let palette: CoverPalette
    /// The edge the light comes from.
    let litEdge: UnitPoint
    /// How much of the cast is shown, 0 to 1, for a cast that is revealed; nil for one that is
    /// always whole. (Only a revealed rim is masked: the mask changes how a whole rim adds its
    /// light on dark glass.)
    var reveal: Double? = nil

    /// The soft edge of the rim's climb, as a share of the edge's length. It runs past the end
    /// of the travel, so the rim is complete once the reveal is (a feather ending exactly at the
    /// top left the top fifth missing).
    private static var feather: Double { 0.2 }
    /// The rim straddles the outline; a mask the size of the frame would cut away its outer half.
    private static var maskOverhang: CGFloat { 1 }

    var body: some View {
        let style = palette.container
        if let wash = palette.containerWash, let rim = palette.containerRim {
            let away = UnitPoint(x: 1 - litEdge.x, y: 1 - litEdge.y)
            ZStack {
                // The wash: light from the edge falling off across the control, not from a
                // point, as far as the reach dial says. It simply fades in with the reveal (a
                // wipe cut it in half).
                shape.fill(LinearGradient(
                    stops: [.init(color: wash, location: 0), .init(color: .clear, location: style.washReach)],
                    startPoint: litEdge, endPoint: away
                ))
                .opacity(reveal ?? 1)
                // The rim catches the light along the lit edge, fading out past the start. It
                // runs on the glass highlight's own path, centred on the outline, so the cast
                // colours that highlight rather than lining the inside of it.
                let stroke = shape.inset(by: -0.5)
                    .stroke(
                        LinearGradient(stops: [.init(color: rim, location: 0), .init(color: .clear, location: 1 - style.rimStart)], startPoint: litEdge, endPoint: away),
                        lineWidth: style.rimWidth
                    )
                if let reveal {
                    stroke.mask { Self.climb(reveal) }
                } else {
                    stroke
                }
            }
            .blendMode(palette.containerBlend)
            .allowsHitTesting(false)
        }
    }

    /// The rim's climb, bottom to top: whole at 1.
    private static func climb(_ amount: Double) -> some View {
        let edge = amount * (1 + feather)
        return LinearGradient(
            stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: min(max(edge - feather, 0), 1)),
                .init(color: .clear, location: min(max(edge, 0.0001), 1)),
            ],
            startPoint: .bottom, endPoint: .top
        )
        .opacity(amount > 0 ? 1 : 0)
        .padding(-maskOverhang)
    }
}
