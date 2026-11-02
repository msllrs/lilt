import AppKit
import Carbon
import SwiftUI

/// A key-combination field, as in System Settings: click it, press the combination. Escape
/// cancels, Delete clears. Combinations without ⌃, ⌥ or ⌘ are turned away (function keys
/// excepted), and `error` shows whatever the owner couldn't do with the last one.
struct ShortcutRecorder: View {
    let shortcut: KeyCombo?
    var error: String? = nil
    let onChange: (KeyCombo?) -> Void
    /// The owner's hot key should stand down while recording, or pressing it toggles instead.
    var onRecordingChange: (Bool) -> Void = { _ in }

    @State private var isRecording = false
    @State private var heldModifiers: UInt32 = 0
    @State private var rejection: String?
    @State private var capture = KeyCapture()

    var body: some View {
        VStack(alignment: .trailing, spacing: Theme.Space.xs) {
            Button(action: toggleRecording) {
                Text(label)
                    .foregroundStyle(isRecording || shortcut == nil ? .secondary : .primary)
                    .padding(.horizontal, Theme.Space.sm)
                    .padding(.vertical, Theme.Space.xs)
                    .background(Capsule().fill(.quaternary))
                    .overlay(Capsule().strokeBorder(isRecording ? Color.accentColor : .clear))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Shortcut")
            .accessibilityValue(shortcut?.displayString ?? "None")
            .accessibilityHint(isRecording ? "Press a key combination, Escape to cancel, Delete to clear" : "Click to record")

            if let message = rejection ?? error {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.trailing)
            }
        }
        .onDisappear { stop() }
    }

    private var label: String {
        guard isRecording else { return shortcut?.displayString ?? "Record Shortcut" }
        return heldModifiers == 0 ? "Type Shortcut" : KeyCombo.modifierSymbols(heldModifiers) + "…"
    }

    private func toggleRecording() {
        isRecording ? stop() : start()
    }

    private func start() {
        rejection = nil
        heldModifiers = 0
        isRecording = true
        onRecordingChange(true)
        capture.start(onEvent: handle, onLostFocus: stop)
    }

    private func stop() {
        guard isRecording else { return }
        capture.stop()
        isRecording = false
        heldModifiers = 0
        onRecordingChange(false)
    }

    private func handle(_ event: NSEvent) {
        if event.type == .flagsChanged {
            heldModifiers = KeyCombo.carbonModifiers(event.modifierFlags)
            return
        }
        let combo = KeyCombo(keyCode: event.keyCode, flags: event.modifierFlags)
        if combo.modifiers == 0 {
            switch Int(combo.keyCode) {
            case kVK_Escape:
                rejection = nil
                stop()
                return
            case kVK_Delete, kVK_ForwardDelete:
                rejection = nil
                stop()
                onChange(nil)
                return
            default: break
            }
        }
        switch combo.validity {
        case .valid:
            rejection = nil
            stop()
            onChange(combo)
        case .needsModifier:
            // Keep listening, so the next try doesn't need another click.
            rejection = "Use ⌃, ⌥ or ⌘ with it, or a function key on its own."
        }
    }
}

/// Key presses for the recorder, through a local monitor: only while Lilt is frontmost, which
/// is when you're recording, so no Accessibility permission. Every press is swallowed, menu
/// shortcuts included, so ⌘W records rather than closes. Clicking into another window cancels.
@MainActor
private final class KeyCapture {
    private var monitor: Any?
    private var resignObserver: NSObjectProtocol?

    func start(onEvent: @escaping (NSEvent) -> Void, onLostFocus: @escaping @MainActor @Sendable () -> Void) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            onEvent(event)
            return event.type == .flagsChanged ? event : nil
        }
        let window = NSApp.keyWindow
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { _ in
            MainActor.assumeIsolated { onLostFocus() }
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        monitor = nil
        resignObserver = nil
    }
}
