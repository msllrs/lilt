import AppKit
import SwiftUI

struct SearchField: View {
    /// Settings ▸ General ▸ Focus search automatically: whether the search screen's field takes
    /// the caret by itself. Off, keys go to the panel's shortcuts until the field is clicked.
    static let autoFocusKey = "searchFocusesAutomatically"

    @Binding var text: String
    var prompt = "Search"
    /// The page the field belongs to; nil for the search screen at the root.
    var screenId: String? = nil
    /// Told when the caret arrives in the field or leaves it.
    var onFocusChange: ((Bool) -> Void)? = nil
    @Environment(NavigationModel.self) private var navigation
    @AppStorage(SearchField.autoFocusKey) private var focusesAutomatically = false
    @FocusState private var isFocused: Bool
    /// Asking again for a caret that was dropped: the focus state goes false and straight back
    /// to true, and the false isn't the caret leaving.
    @State private var isReasking = false
    @State private var host = HostWindow()

    /// Screens stay mounted (parked) under the ones above them; the field only owns focus while
    /// its screen is actually on top, or typing on a page would silently edit another's text.
    private var isOnTop: Bool { screenId == nil ? navigation.path.isEmpty : navigation.path.last?.id == screenId }

    /// Whether the field takes the caret by itself while it's on top. A page's field appears
    /// because it was asked for, so always; the search root's only with the setting.
    private var takesTheCaret: Bool { isOnTop && (screenId != nil || focusesAutomatically) }

    /// Whether the caret is really in the field: its window's field editor is editing this
    /// field's text. The focus state can't say, since it reads true after an ask the window never
    /// saw; nor can a field editor at work alone, since parked screens keep their fields in the
    /// window, and the one editing may be the search root's under a shelf.
    private var isEditing: Bool { host.isEditing }

    var body: some View {
        HStack(spacing: Theme.Space.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .focused($isFocused)
                // An ask made before the field is in a window is dropped; ask again once it's in
                // one. Behind the text itself, so the probe also tells which text field is this one.
                .background(WindowReader(host: host) { DispatchQueue.main.async { claimIfDropped("in a window") } })
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
        // As in any search field on the Mac, the whole of it takes the caret: the glass and the
        // padding around the text, not only the text. The clear button keeps its own click.
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        .onTapGesture { if !isEditing { ask() } }
        .background {
            if ArtworkStyle.shared.headerControls.mode == .flat || !ArtworkStyle.shared.headerControls.appliesToSearch {
                RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous).fill(.fill.quaternary)
            }
        }
        .modifier(SearchSurface())
        .onAppear { claimTheCaret() }
        // Give focus up when a page opens over the search root, take it back when you return.
        .onChange(of: isOnTop) { _, onTop in
            if onTop { claimTheCaret() } else { giveUpTheCaret() }
        }
        .onChange(of: isFocused) { _, focused in
            // A parked field never keeps the caret. Live, a shelf filter's ask landed on the
            // search root beneath it, and the filter opened without the caret; let it go, and
            // the filter's next look finds it free and asks again.
            if focused, !isOnTop {
                Diagnostics.shared.record(.screen, "\(screenId ?? "search"): field gives up the caret it took while parked")
                giveUpTheCaret()
                return
            }
            if isReasking {
                isReasking = false
                // The false half of asking again: ask for real now that the stale ask is
                // cleared, without telling anyone the caret left (a shelf folds its filter then).
                // On top rather than taking the caret by itself: a click asks for it too.
                if !focused, isOnTop { isFocused = true; return }
            }
            Diagnostics.shared.record(.screen, "\(screenId ?? "search"): field focus state \(focused)")
            onFocusChange?(focused)
        }
        // The panel often isn't key when this first appears; re-claim focus when it becomes key
        // so showing the panel means you can type straight away. Only the field's own panel,
        // only while the field takes the caret by itself, and only when it isn't already
        // editing: re-focusing a field that has it selects all its text, which swallowed the
        // second character of anything typed quickly.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            guard let window = note.object as? PanelWindow, window === host.window, takesTheCaret, !isEditing else { return }
            ask()
        }
    }

    /// Asks for the caret, and on the next turn checks it arrived. An ask made before the field
    /// is in a key window is dropped while the focus state still reads true, which left a
    /// library shelf's filter without the caret after its button opened it.
    private func claimTheCaret() {
        guard takesTheCaret else { return }
        ask()
        DispatchQueue.main.async { claimIfDropped("next turn") }
        // A field revealed in a transition (a shelf's filter flowing out of its button's glass)
        // may only be in the window once the transition ends; look again then.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.afterTransition) { claimIfDropped("after the transition") }
    }

    /// Just past `Theme.Motion.standard`, the transition a revealed field arrives in.
    private static let afterTransition: TimeInterval = 0.4

    private func claimIfDropped(_ when: String) {
        do {
            Diagnostics.shared.record(.screen, "\(screenId ?? "search"): field checks its caret (\(when)): on top \(isOnTop), takes it \(takesTheCaret), editing \(isEditing), focus state \(isFocused), window \(host.window.map { "\(type(of: $0)), first responder \(String(describing: $0.firstResponder.map { type(of: $0) }))" } ?? "none")")
        }
        guard takesTheCaret, !isEditing else { return }
        ask()
    }

    /// Lets the caret go. The focus state going false alone left the field editor at work in a
    /// parked field, typing into text nobody could see, so the window lets it go too.
    private func giveUpTheCaret() {
        isFocused = false
        if isEditing { host.window?.makeFirstResponder(nil) }
    }

    /// Asks for the caret. If the focus state already reads true the ask was dropped, and
    /// setting true again would change nothing, so it goes false first and back (above).
    private func ask() {
        do {
            let window = host.window
            Diagnostics.shared.record(.screen, "\(screenId ?? "search"): field asks for the caret (\(window.map { "in \(String(describing: type(of: $0)))\($0.isKeyWindow ? ", key" : ", not key")" } ?? "not in a window yet"), \(isFocused ? "asked before" : "first ask"))")
        }
        if isFocused {
            isReasking = true
            isFocused = false
        } else {
            isFocused = true
        }
    }
}

/// The window the field is in, kept without a view update when it changes, and the probe
/// behind its text.
private final class HostWindow {
    weak var window: NSWindow?
    weak var probe: NSView?

    /// Whether the window's field editor is editing the text field behind the probe. SwiftUI
    /// keeps the text field and its background in views of their own, so they're matched by
    /// place: the text field covers the background it was laid out with. A parked screen's
    /// field sits a page's travel aside, so it never covers this one's.
    var isEditing: Bool {
        guard let probe, let window = probe.window,
              let editor = window.firstResponder as? NSTextView,
              let field = editor.delegate as? NSTextField, field.window === window
        else { return false }
        return field.convert(field.bounds, to: nil).contains(probe.convert(probe.bounds, to: nil))
    }
}

private struct WindowReader: NSViewRepresentable {
    let host: HostWindow
    /// Told when the field arrives in a window.
    let arrived: () -> Void

    func makeNSView(context: Context) -> Probe { Probe(host: host, arrived: arrived) }
    func updateNSView(_ probe: Probe, context: Context) { probe.arrived = arrived }

    final class Probe: NSView {
        let host: HostWindow
        var arrived: () -> Void
        init(host: HostWindow, arrived: @escaping () -> Void) {
            self.host = host
            self.arrived = arrived
            super.init(frame: .zero)
            host.probe = self
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            host.window = window
            if window != nil { arrived() }
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
