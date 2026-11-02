import SwiftUI

/// The cover's light spilling down from the top of a page: the artwork itself, blurred and
/// saturated like the platter's ambient fill, fading out over `reach`. Crossfades between covers.
struct PageAmbient: View {
    let url: URL?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var style: PageAmbientStyle { ArtworkStyle.shared.pageAmbient }
    /// Its strength, saturation and blur, for the window style on screen.
    private var surface: SurfaceStyle.PageAmbient { ArtworkStyle.shared.surface(colorScheme, reduceTransparency: reduceTransparency).pageAmbient }

    private var image: NSImage? {
        guard surface.opacity > 0, let url else { return nil }
        return ImageCache.shared.cached(url) ?? ImageCache.shared.anyVariant(for: url)
    }

    var body: some View {
        ZStack(alignment: .top) {
            if let image {
                // The same band of the cover the platter's wash shows (its wide shape crops to the
                // middle), stretched to the reach, so the page's light and the platter's agree
                // instead of one averaging the whole cover.
                GeometryReader { geometry in
                    let bandHeight = max(geometry.size.width * style.band, 1)
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: bandHeight)
                        .clipped()
                        .saturation(surface.saturation)
                        .scaleEffect(x: 1, y: style.reach / bandHeight, anchor: .top)
                        .blur(radius: surface.blur)
                }
                .id(url)
                .transition(.opacity)
            }
        }
        .frame(height: style.reach)
        .frame(maxWidth: .infinity)
        .clipped()
        .mask {
            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
        }
        .opacity(surface.opacity)
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
        .animation(Theme.Motion.cast, value: url)
    }
}
