import AppKit
import Carbon
import Testing
@testable import Lilt

/// The global show/hide shortcut: how a combination reads, which ones are allowed, how it's
/// kept in defaults, and what a press does to the panel.
@MainActor
struct ShowLiltShortcutTests {
    private let control = UInt32(controlKey), option = UInt32(optionKey), shift = UInt32(shiftKey), command = UInt32(cmdKey)

    /// The US layout, so the tests read the same on any keyboard.
    private func us(_ combo: KeyCombo) -> String {
        combo.displayString { KeyCombo.ansiCharacters[$0] }
    }

    @Test func modifiersReadInMenuOrderBeforeTheKey() {
        #expect(us(KeyCombo(keyCode: UInt32(kVK_ANSI_L), modifiers: command | shift | option | control)) == "⌃⌥⇧⌘L")
        #expect(us(KeyCombo(keyCode: UInt32(kVK_ANSI_L), modifiers: control | option | command)) == "⌃⌥⌘L")
        #expect(us(KeyCombo(keyCode: UInt32(kVK_ANSI_1), modifiers: command)) == "⌘1")
        #expect(us(KeyCombo(keyCode: UInt32(kVK_ANSI_Slash), modifiers: shift | command)) == "⇧⌘/")
    }

    @Test func namedKeysUseTheirMenuSymbols() {
        #expect(us(KeyCombo(keyCode: UInt32(kVK_Space), modifiers: option)) == "⌥Space")
        #expect(us(KeyCombo(keyCode: UInt32(kVK_Return), modifiers: command)) == "⌘↩")
        #expect(us(KeyCombo(keyCode: UInt32(kVK_LeftArrow), modifiers: control)) == "⌃←")
        #expect(us(KeyCombo(keyCode: UInt32(kVK_ForwardDelete), modifiers: command)) == "⌘⌦")
        #expect(us(KeyCombo(keyCode: UInt32(kVK_F5), modifiers: 0)) == "F5")
        #expect(us(KeyCombo(keyCode: UInt32(kVK_F19), modifiers: shift)) == "⇧F19")
    }

    @Test func aKeyNobodyNamesStillReadsAsSomething() {
        #expect(KeyCombo(keyCode: 999, modifiers: command).displayString { _ in nil } == "⌘Key 999")
    }

    @Test func modifiersOutsideTheFourAreDropped() {
        let combo = KeyCombo(keyCode: UInt32(kVK_ANSI_A), modifiers: command | UInt32(alphaLock))
        #expect(combo.modifiers == command)
        #expect(KeyCombo(keyCode: UInt16(kVK_ANSI_A), flags: [.command, .capsLock, .function]) == KeyCombo(keyCode: UInt32(kVK_ANSI_A), modifiers: command))
    }

    @Test func aShortcutNeedsControlOptionOrCommand() {
        #expect(KeyCombo(keyCode: UInt32(kVK_ANSI_L), modifiers: 0).validity == .needsModifier)
        // ⇧ alone only capitalises.
        #expect(KeyCombo(keyCode: UInt32(kVK_ANSI_L), modifiers: shift).validity == .needsModifier)
        #expect(KeyCombo(keyCode: UInt32(kVK_Space), modifiers: 0).validity == .needsModifier)
        #expect(KeyCombo(keyCode: UInt32(kVK_ANSI_L), modifiers: control).validity == .valid)
        #expect(KeyCombo(keyCode: UInt32(kVK_Space), modifiers: option).validity == .valid)
        #expect(KeyCombo(keyCode: UInt32(kVK_ANSI_L), modifiers: shift | command).validity == .valid)
    }

    @Test func functionKeysCanGoWithoutAModifier() {
        #expect(KeyCombo(keyCode: UInt32(kVK_F1), modifiers: 0).validity == .valid)
        #expect(KeyCombo(keyCode: UInt32(kVK_F13), modifiers: 0).validity == .valid)
        #expect(KeyCombo(keyCode: UInt32(kVK_F20), modifiers: shift).validity == .valid)
    }

    @Test func theDefaultIsAllowed() {
        #expect(ShowLiltShortcut.defaultCombo.validity == .valid)
        #expect(us(ShowLiltShortcut.defaultCombo) == "⌃⌥⌘L")
    }

    /// The real defaults Lilt reads at launch (tests run inside Lilt.app), put back afterwards.
    @Test func theShortcutSurvivesARelaunch() {
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: ShowLiltShortcut.key)
        defer { defaults.set(saved, forKey: ShowLiltShortcut.key) }

        defaults.removeObject(forKey: ShowLiltShortcut.key)
        #expect(ShowLiltShortcut.load(from: defaults) == ShowLiltShortcut.defaultCombo)

        let combo = KeyCombo(keyCode: UInt32(kVK_F6), modifiers: shift | command)
        ShowLiltShortcut.save(combo, to: defaults)
        #expect(ShowLiltShortcut.load(from: defaults) == combo)
        let stored = defaults.dictionary(forKey: ShowLiltShortcut.key)
        #expect(stored?["keyCode"] as? Int == kVK_F6)
        #expect(stored?["modifiers"] as? Int == Int(shift | command))

        // Cleared stays cleared, rather than falling back to the default.
        ShowLiltShortcut.save(nil, to: defaults)
        #expect(ShowLiltShortcut.load(from: defaults) == nil)
    }

    @Test func onlyAShownKeyPanelHides() {
        #expect(AppDelegate.shortcutHidesPanel(isHidden: false, isKey: true))
        #expect(!AppDelegate.shortcutHidesPanel(isHidden: false, isKey: false))
        #expect(!AppDelegate.shortcutHidesPanel(isHidden: true, isKey: false))
        // Hidden by alpha, a panel can still hold key; it comes back rather than hiding again.
        #expect(!AppDelegate.shortcutHidesPanel(isHidden: true, isKey: true))
    }
}
