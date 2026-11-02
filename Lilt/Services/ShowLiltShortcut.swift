import Carbon
import Foundation
import Observation

/// The system-wide shortcut that shows or hides the panel: what it is, whether it registered,
/// and where it's kept. Settings records it; AppDelegate decides what a press does.
@MainActor
@Observable
final class ShowLiltShortcut {
    static let key = "showLiltShortcut"

    /// ⌃⌥⌘L, after the in-app ⌘⇧L. ⌥Space was the first idea, but it types a non-breaking
    /// space, and Raycast, Alfred, ChatGPT and Claude all offer it for their own launchers.
    static let defaultCombo = KeyCombo(keyCode: UInt32(kVK_ANSI_L), modifiers: UInt32(controlKey | optionKey | cmdKey))

    /// Nil when cleared: no shortcut at all.
    private(set) var combo: KeyCombo?
    /// Why the shortcut isn't working, for Settings to show beside it.
    private(set) var error: String?

    @ObservationIgnored private let hotKey: GlobalHotKey
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, action: @escaping () -> Void) {
        self.defaults = defaults
        hotKey = GlobalHotKey(action: action)
        combo = Self.load(from: defaults)
        // The saved shortcut is kept even if it can't register now (another app holds it);
        // Settings says so.
        if let combo { error = Self.register(combo, with: hotKey) }
    }

    /// Saves and registers `newCombo`. If it can't register, the previous shortcut stays.
    func set(_ newCombo: KeyCombo?) {
        guard let newCombo else {
            hotKey.unregister()
            combo = nil
            error = nil
            Self.save(nil, to: defaults)
            return
        }
        if let failure = Self.register(newCombo, with: hotKey) {
            if let combo { _ = Self.register(combo, with: hotKey) }
            error = failure
            return
        }
        combo = newCombo
        error = nil
        Self.save(newCombo, to: defaults)
    }

    /// While a recorder listens, the hot key stands down; otherwise pressing the current
    /// shortcut would toggle the panel instead of being recorded.
    func setSuspended(_ suspended: Bool) {
        if suspended {
            hotKey.unregister()
        } else if let combo {
            error = Self.register(combo, with: hotKey)
        }
    }

    /// The message for a failed registration, or nil on success.
    private static func register(_ combo: KeyCombo, with hotKey: GlobalHotKey) -> String? {
        switch hotKey.register(combo) {
        case .success: nil
        case .failure(.takenBySystem): "\(combo.displayString) is already a macOS shortcut."
        case .failure(.taken): "\(combo.displayString) is in use by another app."
        case .failure(.failed(let status)): "\(combo.displayString) couldn't be registered (\(status))."
        }
    }

    // MARK: Persistence

    /// Kept as `["keyCode": Int, "modifiers": Int]`, one key so the two can't drift apart. No
    /// entry means the default; an empty one means cleared.
    static func load(from defaults: UserDefaults) -> KeyCombo? {
        guard let saved = defaults.dictionary(forKey: key) else { return defaultCombo }
        guard let keyCode = saved["keyCode"] as? Int, let modifiers = saved["modifiers"] as? Int else { return nil }
        return KeyCombo(keyCode: UInt32(keyCode), modifiers: UInt32(modifiers))
    }

    static func save(_ combo: KeyCombo?, to defaults: UserDefaults) {
        let saved: [String: Int] = combo.map { ["keyCode": Int($0.keyCode), "modifiers": Int($0.modifiers)] } ?? [:]
        defaults.set(saved, forKey: key)
    }
}
