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

/// A section header that folds its rows when clicked.
///
/// Emitted as a `Section`, so inside the screen's lazy stack the header and each row are
/// separate lazy children and only the rows on screen are built (a plain stack around the rows
/// built a whole library the moment the screen appeared, felt as a pause). The fold is the same
/// as ever to look at, rows standing still while the section's visible height shrinks from the
/// bottom, but expressed per row: each row knows its place and clips itself to the part of the
/// section still showing.
struct CollapsibleSection<Item: Identifiable, Row: View, Empty: View>: View {
    let title: String
    /// Distinguishes sections with the same title on different screens.
    let scope: String
    let items: [Item]
    /// How many rows exist yet, when a screen builds its rows in slices (see LibraryScreen);
    /// nil builds them all.
    var limit: Int? = nil
    @ViewBuilder let row: (Item) -> Row
    /// Shown in place of rows when there are none.
    @ViewBuilder let empty: () -> Empty

    @Environment(CollapsedSections.self) private var collapsedSections
    /// An album page's cover colour, for the header; the rows are left to their own.
    @Environment(\.coverPalette) private var coverPalette
    @State private var isHovering = false

    private var id: String { "\(scope)/\(title)" }
    private var isCollapsed: Bool { collapsedSections.isCollapsed(id) }

    init(title: String, scope: String, items: [Item], limit: Int? = nil, @ViewBuilder row: @escaping (Item) -> Row, @ViewBuilder empty: @escaping () -> Empty) {
        self.title = title
        self.scope = scope
        self.items = items
        self.limit = limit
        self.row = row
        self.empty = empty
    }

    private var built: [Item] { limit.map { Array(items.prefix($0)) } ?? items }

    var body: some View {
        Section {
            if !isCollapsed {
                ForEach(Array(built.enumerated()), id: \.element.id) { index, item in
                    row(item)
                        .transition(.fold(index: index, count: built.count))
                }
                if items.isEmpty {
                    empty()
                        .transition(.opacity)
                }
            }
        } header: {
            Button {
                withAnimation(Theme.Motion.standard) { collapsedSections.toggle(id) }
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
                .foregroundStyle(coverPalette.style(\.secondary, or: .secondary))
                .padding(.horizontal, Theme.Space.rowPadding)
                .padding(.top, Theme.Space.lg)
                .padding(.bottom, Theme.Space.xs)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
        }
    }
}

extension CollapsibleSection where Empty == EmptyView {
    init(title: String, scope: String, items: [Item], limit: Int? = nil, @ViewBuilder row: @escaping (Item) -> Row) {
        self.init(title: title, scope: scope, items: items, limit: limit, row: row, empty: { EmptyView() })
    }
}

/// One row's part in the section fold. The section's visible height runs from all its rows to
/// nothing (or back); a row shows the slice of itself that falls within it, clipped at the
/// bottom and fading as it goes, and nothing once the edge has passed it. All rows share one
/// clock, so the whole reads as the old single clip: rows still, the edge sweeping up.
nonisolated private struct FoldRow: ViewModifier, Animatable {
    var progress: Double
    let index: Int
    let count: Int

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let height = Theme.Size.row
        let visible = CGFloat(count) * height * (1 - progress)
        let mine = min(max(visible - CGFloat(index) * height, 0), height)
        content
            .frame(height: mine, alignment: .top)
            // Clipped only while the edge is passing through this row. Rows it hasn't reached,
            // and rows at rest, keep the clip far outside them so the cover's ambient shadow
            // spills past the row as it always has; clipping every row for the whole fold cut
            // all their shadows square at once and brought them back at the end.
            .clipShape(Rectangle().inset(by: mine < height ? 0 : -height * 4))
            .opacity(mine / height)
    }
}

extension AnyTransition {
    static func fold(index: Int, count: Int) -> AnyTransition {
        .modifier(active: FoldRow(progress: 1, index: index, count: count), identity: FoldRow(progress: 0, index: index, count: count))
    }
}
