import SwiftUI

extension View {
    /// The edge treatment every list in the panel shares where it scrolls under a header or the
    /// platter. The headers draw their own blur (see `HeaderBackdrop`).
    func panelScrollEdge() -> some View {
        scrollEdgeEffectStyle(.soft, for: .all)
    }
}
