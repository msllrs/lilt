import SwiftUI

/// The cover's light spilling down from the top of a page: the artwork itself, blurred and
/// saturated like the platter's ambient fill, fading out over `reach`. Crossfades between covers.
struct PageAmbient: View {
    let url: URL?

    private var style: PageAmbientStyle { ArtworkStyle.shared.pageAmbient }

    private var image: NSImage? {
        guard style.opacity > 0, let url else { return nil }
        return ImageCache.shared.cached(url) ?? ImageCache.shared.anyVariant(for: url)
    }

    var body: some View {
        ZStack(alignment: .top) {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .saturation(style.saturation)
                    .blur(radius: style.blur)
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
        .opacity(style.opacity)
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
        .animation(Theme.Motion.cast, value: url)
    }
}
