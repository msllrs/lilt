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
    /// 0 open, 1 folded; animated so the fade tracks the clip.
    @State private var fold: CGFloat

    private var id: String { "\(scope)/\(title)" }
    private var isCollapsed: Bool { collapsedSections.isCollapsed(id) }

    init(title: String, scope: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.scope = scope
        self.content = content
        _fold = State(initialValue: MainActor.assumeIsolated {
            AppDelegate.shared?.collapsedSections.isCollapsed("\(scope)/\(title)") == true ? 1 : 0
        })
    }

    var body: some View {
        Button {
            withAnimation(Theme.Motion.standard) {
                collapsedSections.toggle(id)
                fold = isCollapsed ? 1 : 0
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.xs) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .kerning(0.6)
                // Caps have no descenders, so the glyph sits on the baseline and is lifted to
                // the optical middle of the cap height.
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                    .opacity(isHovering || isCollapsed ? 1 : 0)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4.5 }
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

        // Rows reveal from under the title and fold back behind it: a height clip, so nothing
        // ever draws over the header. While folding, the bottom edge fades rather than cuts.
        // Clip and fade apply only while folding or folded; an open section is left untouched
        // so the last row's ambient shadow can spill past the section as usual.
        // A lazy stack of its own, nested in the screen's: the rows stay one view for the clip,
        // but only those near the viewport are built. A plain stack built every row the moment
        // the screen appeared (a whole library at once), felt as a pause before it showed.
        LazyVStack(spacing: 0) { content() }
            .frame(maxHeight: isCollapsed ? 0 : nil, alignment: .top)
            .mask {
                if fold > 0 {
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: 1 - 0.35 * fold),
                            .init(color: .black.opacity(1 - fold), location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                } else {
                    // Oversized so shadows past the frame survive.
                    Rectangle().padding(-40)
                }
            }
            .allowsHitTesting(!isCollapsed)
    }
}
