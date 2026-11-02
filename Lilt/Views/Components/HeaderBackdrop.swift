import SwiftUI

/// A progressive blur behind a header that floats over scrolling content.
///
/// macOS 26's own scroll-edge effect is the right tool for this, and the headers are declared as
/// safe-area bars so they'd receive it, but it doesn't render inside a borderless AppKit-hosted
/// window. Until it does, this uses the system material and fades it out below the header so rows
/// melt into the blur instead of clashing with the header text.
struct HeaderBackdrop: ViewModifier {
    /// How far the blur reaches below the header before fading to nothing.
    var reach: CGFloat = 32
    /// 0 while the list is at rest (nothing is under the header yet), 1 once content scrolls
    /// beneath it. Keeps the blur off the hero artwork on an unscrolled page.
    var visibility: CGFloat = 1

    private var style: HeaderBlurStyle { ArtworkStyle.shared.headerBlur }
    /// The surface `PanelBackground` actually mounts decides whether there is a glass rim to
    /// redraw, and the blur's values are that surface's.
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    /// The panel corner the backdrop is clipped to. Behind-window layers ignore the window's own
    /// corner clip, so this applies under the native frame too.
    static let clipRadius: CGFloat = Theme.Radius.window

    func body(content: Content) -> some View {
        let useBackdrop = style.useBackdrop && ProgressiveBlurBackdrop.isAvailable
        let blur = ArtworkStyle.shared.surface(colorScheme, reduceTransparency: reduceTransparency).headerBlur
        let reach = useBackdrop ? CGFloat(blur.reach) : self.reach
        content.background(alignment: .top) {
            GeometryReader { geometry in
                let fadeStart = geometry.size.height / (geometry.size.height + reach)
                Group {
                    if useBackdrop {
                        // A true blur ramp: strongest under the header, gone by `reach`. The
                        // saturation boost re-saturates what a material's grey tint washes out;
                        // blurring Lilt's own content there is no tint, and a boost turns a red
                        // cover passing under the header into a magenta flare, so it is left at 1.
                        ProgressiveBlurBackdrop(radius: blur.radius, saturation: style.ownContentOnly ? 1 : blur.saturation, brightness: blur.brightness, fadeStart: fadeStart, cornerRadius: Self.clipRadius, ownContentOnly: style.ownContentOnly)
                    } else {
                        Rectangle()
                            .fill(.thinMaterial)
                            .mask {
                                LinearGradient(
                                    stops: [
                                        .init(color: .black, location: 0),
                                        .init(color: .black, location: fadeStart),
                                        .init(color: .clear, location: 1),
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            }
                    }
                }
                .frame(height: geometry.size.height + reach)
                // The backdrop blurs the window glass's own hairline rim away where it covers
                // it; draw the rim back on top, just within this region.
                .overlay(alignment: .top) {
                    // Only the glass surface has a rim to restore; the sidebar's hairline sits
                    // above the blur already.
                    if useBackdrop, ArtworkStyle.shared.panel.effective(reduceTransparency: reduceTransparency).surface == .glass {
                        Color.clear
                            .frame(height: Theme.Radius.window * 4)
                            .glassEdge(RoundedRectangle(cornerRadius: Theme.Radius.window, style: .continuous).inset(by: 0.5), opacity: blur.rimOpacity)
                            .frame(height: geometry.size.height + reach, alignment: .top)
                            // Fades out with the blur, so it hands back to the real rim below.
                            .mask {
                                LinearGradient(
                                    stops: [
                                        .init(color: .black, location: 0),
                                        .init(color: .black, location: fadeStart),
                                        .init(color: .clear, location: 1),
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            }
                    }
                }
                .opacity(visibility)
            }
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
        }
    }
}

extension View {
    /// - Parameter visibility: pass a value derived from scroll offset so the blur only appears
    ///   once content is actually under the header.
    func headerBackdrop(reach: CGFloat = 32, visibility: CGFloat = 1) -> some View {
        modifier(HeaderBackdrop(reach: reach, visibility: visibility))
    }

    /// Maps a scroll offset to backdrop visibility: fully in after `distance` points of scroll.
    static func backdropVisibility(forScrollOffset offset: CGFloat, distance: CGFloat = 24) -> CGFloat {
        min(max(offset / distance, 0), 1)
    }
}
