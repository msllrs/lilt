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

    func body(content: Content) -> some View {
        content.background(alignment: .top) {
            GeometryReader { geometry in
                Rectangle()
                    .fill(.thinMaterial)
                    .mask {
                        LinearGradient(
                            stops: [
                                .init(color: .black, location: 0),
                                .init(color: .black, location: geometry.size.height / (geometry.size.height + reach)),
                                .init(color: .clear, location: 1),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    .frame(height: geometry.size.height + reach)
            }
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
        }
    }
}

extension View {
    func headerBackdrop(reach: CGFloat = 32) -> some View {
        modifier(HeaderBackdrop(reach: reach))
    }
}
