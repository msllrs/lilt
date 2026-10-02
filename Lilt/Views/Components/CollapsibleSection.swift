import SwiftUI

/// Which sections are folded up, remembered per screen across launches.
@MainActor
@Observable
final class CollapsedSections {
    private static let key = "collapsedSections"
    private var collapsed: Set<String>

    init() {
        collapsed = Set(UserDefaults.standard.stringArray(forKey: Self.key) ?? [])
    }

    func isCollapsed(_ id: String) -> Bool { collapsed.contains(id) }

    func toggle(_ id: String) {
        if !collapsed.insert(id).inserted { collapsed.remove(id) }
        UserDefaults.standard.set(Array(collapsed), forKey: Self.key)
    }
}

/// A section header that folds its content when clicked.
struct CollapsibleSection<Content: View>: View {
    let title: String
    /// Distinguishes sections with the same title on different screens.
    let scope: String
    @ViewBuilder let content: () -> Content

    @Environment(CollapsedSections.self) private var collapsedSections
    @State private var isHovering = false

    private var id: String { "\(scope)/\(title)" }
    private var isCollapsed: Bool { collapsedSections.isCollapsed(id) }

    var body: some View {
        Button {
            withAnimation(Theme.Motion.standard) { collapsedSections.toggle(id) }
        } label: {
            HStack(spacing: Theme.Space.xs) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .kerning(0.6)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                    .opacity(isHovering || isCollapsed ? 1 : 0)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, Theme.Space.sm)
            .padding(.top, Theme.Space.lg)
            .padding(.bottom, Theme.Space.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }

        if !isCollapsed {
            content()
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}
