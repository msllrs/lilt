import AppKit
import Carbon

/// A key and its modifiers, the way Carbon's `RegisterEventHotKey` wants them: a virtual key
/// code and a Carbon modifier mask (`cmdKey`, `optionKey`…). Kept in that form, not
/// `NSEvent.ModifierFlags`, so what's stored is exactly what gets registered.
struct KeyCombo: Equatable, Hashable, Sendable {
    let keyCode: UInt32
    /// Only the four Carbon modifier bits; caps lock and the rest are dropped.
    let modifiers: UInt32

    static let modifierMask = UInt32(controlKey | optionKey | shiftKey | cmdKey)

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers & Self.modifierMask
    }

    init(keyCode: UInt16, flags: NSEvent.ModifierFlags) {
        self.init(keyCode: UInt32(keyCode), modifiers: Self.carbonModifiers(flags))
    }

    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var mask: UInt32 = 0
        if flags.contains(.control) { mask |= UInt32(controlKey) }
        if flags.contains(.option) { mask |= UInt32(optionKey) }
        if flags.contains(.shift) { mask |= UInt32(shiftKey) }
        if flags.contains(.command) { mask |= UInt32(cmdKey) }
        return mask
    }

    // MARK: Validation

    enum Validity: Equatable {
        case valid
        /// A plain key (or one with only ⇧) would swallow ordinary typing everywhere.
        case needsModifier
    }

    var validity: Validity {
        if Self.functionKeys[keyCode] != nil { return .valid }
        return modifiers & UInt32(controlKey | optionKey | cmdKey) != 0 ? .valid : .needsModifier
    }

    // MARK: Display

    /// Modifiers in the order macOS menus print them, then the key: ⌃⌥⇧⌘L.
    static func modifierSymbols(_ modifiers: UInt32) -> String {
        var symbols = ""
        if modifiers & UInt32(controlKey) != 0 { symbols += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { symbols += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { symbols += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { symbols += "⌘" }
        return symbols
    }

    var displayString: String { displayString(characterName: Self.layoutCharacter) }

    /// `characterName` names character keys (letters, digits, punctuation), which move between
    /// keyboard layouts; it defaults to the current layout. Named keys and function keys don't
    /// move, so they come from fixed tables. Falls back to the US layout, then the bare code.
    func displayString(characterName: (UInt32) -> String?) -> String {
        let key = Self.namedKeys[keyCode]
            ?? Self.functionKeys[keyCode]
            ?? characterName(keyCode)
            ?? Self.ansiCharacters[keyCode]
            ?? "Key \(keyCode)"
        return Self.modifierSymbols(modifiers) + key
    }

    /// The character the current keyboard layout prints on that key, uppercased, as menus show it.
    static func layoutCharacter(_ keyCode: UInt32) -> String? {
        // Input methods (Japanese, Chinese) carry no layout data of their own.
        let sources = [TISCopyCurrentKeyboardLayoutInputSource(), TISCopyCurrentASCIICapableKeyboardLayoutInputSource()]
        for case let source? in sources.map({ $0?.takeRetainedValue() }) {
            guard let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { continue }
            let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
            var deadKeys: UInt32 = 0
            var length = 0
            var characters = [UniChar](repeating: 0, count: 4)
            let status = data.withUnsafeBytes { raw in
                UCKeyTranslate(
                    raw.baseAddress!.assumingMemoryBound(to: UCKeyboardLayout.self),
                    UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                    OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, characters.count, &length, &characters
                )
            }
            guard status == noErr, length > 0 else { continue }
            let name = String(utf16CodeUnits: characters, count: length).uppercased()
            if !name.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters)).isEmpty { return name }
        }
        return nil
    }

    static let functionKeys: [UInt32: String] = {
        let codes = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                     kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]
        return Dictionary(uniqueKeysWithValues: codes.enumerated().map { (UInt32($0.element), "F\($0.offset + 1)") })
    }()

    /// Keys that print the same symbol on every layout, as in macOS menus.
    static let namedKeys: [UInt32: String] = [
        UInt32(kVK_Space): "Space",
        UInt32(kVK_Return): "↩",
        UInt32(kVK_ANSI_KeypadEnter): "⌤",
        UInt32(kVK_Tab): "⇥",
        UInt32(kVK_Delete): "⌫",
        UInt32(kVK_ForwardDelete): "⌦",
        UInt32(kVK_Escape): "⎋",
        UInt32(kVK_LeftArrow): "←",
        UInt32(kVK_RightArrow): "→",
        UInt32(kVK_UpArrow): "↑",
        UInt32(kVK_DownArrow): "↓",
        UInt32(kVK_Home): "↖",
        UInt32(kVK_End): "↘",
        UInt32(kVK_PageUp): "⇞",
        UInt32(kVK_PageDown): "⇟",
        UInt32(kVK_Help): "Help",
    ]

    /// The US layout, for when the current one can't be read.
    static let ansiCharacters: [UInt32: String] = {
        let pairs: [(Int, String)] = [
            (kVK_ANSI_A, "A"), (kVK_ANSI_B, "B"), (kVK_ANSI_C, "C"), (kVK_ANSI_D, "D"), (kVK_ANSI_E, "E"),
            (kVK_ANSI_F, "F"), (kVK_ANSI_G, "G"), (kVK_ANSI_H, "H"), (kVK_ANSI_I, "I"), (kVK_ANSI_J, "J"),
            (kVK_ANSI_K, "K"), (kVK_ANSI_L, "L"), (kVK_ANSI_M, "M"), (kVK_ANSI_N, "N"), (kVK_ANSI_O, "O"),
            (kVK_ANSI_P, "P"), (kVK_ANSI_Q, "Q"), (kVK_ANSI_R, "R"), (kVK_ANSI_S, "S"), (kVK_ANSI_T, "T"),
            (kVK_ANSI_U, "U"), (kVK_ANSI_V, "V"), (kVK_ANSI_W, "W"), (kVK_ANSI_X, "X"), (kVK_ANSI_Y, "Y"),
            (kVK_ANSI_Z, "Z"),
            (kVK_ANSI_0, "0"), (kVK_ANSI_1, "1"), (kVK_ANSI_2, "2"), (kVK_ANSI_3, "3"), (kVK_ANSI_4, "4"),
            (kVK_ANSI_5, "5"), (kVK_ANSI_6, "6"), (kVK_ANSI_7, "7"), (kVK_ANSI_8, "8"), (kVK_ANSI_9, "9"),
            (kVK_ANSI_Minus, "-"), (kVK_ANSI_Equal, "="), (kVK_ANSI_LeftBracket, "["), (kVK_ANSI_RightBracket, "]"),
            (kVK_ANSI_Backslash, "\\"), (kVK_ANSI_Semicolon, ";"), (kVK_ANSI_Quote, "'"), (kVK_ANSI_Comma, ","),
            (kVK_ANSI_Period, "."), (kVK_ANSI_Slash, "/"), (kVK_ANSI_Grave, "`"),
        ]
        return Dictionary(uniqueKeysWithValues: pairs.map { (UInt32($0.0), $0.1) })
    }()
}
