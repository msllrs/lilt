import SwiftUI

struct SearchField: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: Theme.Space.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search", text: $text)
                .textFieldStyle(.plain)
                .focused($isFocused)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .font(.body)
        .padding(.horizontal, Theme.Space.md)
        .frame(height: Theme.Size.headerRow)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        .onAppear { isFocused = true }
        // The panel often isn't key when this first appears; re-claim focus when it becomes key
        // so showing the panel means you can type straight away.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            isFocused = true
        }
    }
}
