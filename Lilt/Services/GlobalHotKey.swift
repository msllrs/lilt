import Carbon

/// One system-wide key combination, through Carbon's `RegisterEventHotKey`: it works in the
/// sandbox without Accessibility permission and consumes the key, unlike a global NSEvent
/// monitor, which needs Accessibility and only watches.
@MainActor
final class GlobalHotKey {
    enum Failure: Error, Equatable {
        /// A macOS shortcut (System Settings ▸ Keyboard ▸ Keyboard Shortcuts) already uses it.
        case takenBySystem
        /// Another app registered it first.
        case taken
        case failed(OSStatus)
    }

    private let action: () -> Void
    private let id: UInt32
    private static var nextID: UInt32 = 1
    // Touched only on the main actor; nonisolated so deinit can release them.
    nonisolated(unsafe) private var hotKey: EventHotKeyRef?
    nonisolated(unsafe) private var handler: EventHandlerRef?

    /// 'Lilt', so our events are told apart from anyone else's in the process.
    private static let signature: OSType = 0x4C69_6C74

    init(action: @escaping () -> Void) {
        self.action = action
        id = Self.nextID
        Self.nextID += 1
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var pressed = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed)
            guard status == noErr, pressed.signature == GlobalHotKey.signature else { return OSStatus(eventNotHandledErr) }
            // Carbon delivers hot keys on the main thread's event loop.
            return MainActor.assumeIsolated {
                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                guard pressed.id == hotKey.id else { return OSStatus(eventNotHandledErr) }
                hotKey.action()
                return noErr
            }
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }

    /// Replaces whatever this hot key held. On failure it holds nothing.
    func register(_ combo: KeyCombo) -> Result<Void, Failure> {
        unregister()
        if Self.isTakenBySystem(combo) { return .failure(.takenBySystem) }
        var ref: EventHotKeyRef?
        // Exclusive, so a combination another app holds fails here instead of firing in both.
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, EventHotKeyID(signature: Self.signature, id: id),
                                         GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &ref)
        switch status {
        case noErr:
            hotKey = ref
            return .success(())
        case OSStatus(eventHotKeyExistsErr):
            return .failure(.taken)
        default:
            return .failure(.failed(status))
        }
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
    }

    /// The system's own shortcuts (Spotlight, input sources, Mission Control) aren't Carbon hot
    /// keys, so registering over one succeeds and then never fires. Ask for them directly.
    static func isTakenBySystem(_ combo: KeyCombo) -> Bool {
        var unmanaged: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&unmanaged) == noErr,
              let entries = unmanaged?.takeRetainedValue() as? [[String: Any]] else { return false }
        return entries.contains { entry in
            guard (entry[kHISymbolicHotKeyEnabled as String] as? Bool) == true,
                  let code = entry[kHISymbolicHotKeyCode as String] as? Int,
                  let modifiers = entry[kHISymbolicHotKeyModifiers as String] as? Int else { return false }
            return KeyCombo(keyCode: UInt32(code), modifiers: UInt32(truncatingIfNeeded: modifiers)) == combo
        }
    }
}
