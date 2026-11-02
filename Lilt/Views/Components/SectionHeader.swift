import SwiftUI

struct SectionHeader: View {
    let title: String
    @Environment(\.coverPalette) private var coverPalette

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(coverPalette.style(\.secondary, or: .secondary))
            .textCase(.uppercase)
            .kerning(0.6)
            .padding(.horizontal, Theme.Space.rowPadding)
            .padding(.top, Theme.Space.lg)
            .padding(.bottom, Theme.Space.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
