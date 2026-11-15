import SwiftUI

struct SearchField: View {
    @Binding var text: String
    @Environment(NavigationModel.self) private var navigation
    @FocusState private var isFocused: Bool

    /// The search screen stays mounted (parked) under pages; the field only owns focus while
    /// it's actually the screen on top, or typing on a page would silently edit the query.
    private var isOnTop: Bool { navigation.path.isEmpty }

    var body: some View {
        HStack(spacing: Theme.Space.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search", text: $text)
                .textFieldStyle(.plain)
                .focused($isFocused)
                // As in any search field on the Mac: Escape lets the search go, and the field
                // keeps the caret for the next one.
                .onKeyPress(.escape) {
                    guard !text.isEmpty else { return .ignored }
                    text = ""
                    return .handled
                }
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear")
                .accessibilityLabel("Clear Search")
            }
        }
        .font(.body)
        .padding(.horizontal, Theme.Space.md)
        .frame(height: Theme.Size.headerRow)
        .background {
            if ArtworkStyle.shared.headerControls.mode == .flat || !ArtworkStyle.shared.headerControls.appliesToSearch {
                RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous).fill(.fill.quaternary)
            }
        }
        .modifier(SearchSurface())
        .onAppear { isFocused = isOnTop }
        // Give focus up when a page opens over the search root, take it back when you return.
        .onChange(of: isOnTop) { _, onTop in isFocused = onTop }
        // The panel often isn't key when this first appears; re-claim focus when it becomes key
        // so showing the panel means you can type straight away. Only our panel, only on the
        // search root, and only when the field doesn't already have focus: re-focusing a field
        // that has it selects all its text, which swallowed the second character of anything
        // typed quickly.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            guard (note.object as? NSWindow) is PanelWindow, isOnTop, !isFocused else { return }
            isFocused = true
        }
    }
}

/// The search field's glass surface, only when the header-control mode applies to it.
private struct SearchSurface: ViewModifier {
    func body(content: Content) -> some View {
        let style = ArtworkStyle.shared.headerControls
        if style.mode != .flat, style.appliesToSearch {
            content.headerSurface()
        } else {
            content
        }
    }
}
