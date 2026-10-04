import SwiftUI

/// The header controls' surface: a small round piece of Liquid Glass with the same lit rim as
/// the play capsule and platter, interactive so it responds under the pointer. Also used, as a
/// capsule, for the search field.
struct GlassControl<S: InsettableShape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        content
            .glassEffect(.regular.interactive(), in: shape)
            .glassEdge(shape, opacity: 0.6)
            // Glass pixels are transparent to the window server; keep the control clickable.
            .background { shape.fill(Color.black.opacity(0.012)) }
            .contentShape(shape)
    }
}

extension View {
    /// A round glass button surface for a header control of `Theme.Size.headerRow` size.
    func glassControl() -> some View {
        frame(width: Theme.Size.headerRow, height: Theme.Size.headerRow)
            .modifier(GlassControl(shape: Circle()))
    }

    func glassControl<S: InsettableShape>(_ shape: S) -> some View {
        modifier(GlassControl(shape: shape))
    }
}
