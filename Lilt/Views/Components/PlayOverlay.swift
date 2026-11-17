import SwiftUI

/// A play (or pause) glyph over artwork, shown on hover. The caller owns the action. Built only
/// while it shows: a list's rows each carry one, and only the row under the pointer shows it.
struct PlayOverlay: ViewModifier {
    let isVisible: Bool
    let symbol: String
    let radius: CGFloat
    let size: CGFloat

    func body(content: Content) -> some View {
        content.overlay {
            ZStack {
                if isVisible {
                    #if DEBUG
                    let _ = RowBuildCounts.notePart("playOverlay")
                    #endif
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(.black.opacity(0.45))
                        .overlay {
                            Image(systemName: symbol)
                                .font(.system(size: max(10, size * 0.36), weight: .bold))
                                .foregroundStyle(.white)
                        }
                }
            }
            // In and out at once, whatever animation the hover came with.
            .animation(nil, value: isVisible)
        }
    }
}

extension View {
    func playOverlay(isVisible: Bool, symbol: String = "play.fill", radius: CGFloat, size: CGFloat) -> some View {
        modifier(PlayOverlay(isVisible: isVisible, symbol: symbol, radius: radius, size: size))
    }
}
