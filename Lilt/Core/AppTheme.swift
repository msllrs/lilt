import AppKit

/// Settings ▸ Appearance ▸ Theme: the app follows the system, or stays light or dark whatever
/// the system is in. It is set on `NSApp.appearance`, so every window takes it (the panel, the
/// mini player, Settings and its window style previews) and SwiftUI's colour scheme follows.
enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark

    static let key = "appTheme"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// nil follows the system.
    var appearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    /// The stored choice; a missing or unknown name follows the system.
    static func stored(in defaults: UserDefaults = .standard) -> AppTheme {
        defaults.string(forKey: key).flatMap(AppTheme.init(rawValue:)) ?? .system
    }

    func store(in defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.key)
    }

    @MainActor func apply() {
        NSApp.appearance = appearance
    }
}
