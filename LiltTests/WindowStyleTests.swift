import AppKit
import Testing
@testable import Lilt

/// Settings ▸ Appearance ▸ Window style: Glass, Normal or Solid, stored by name and read back
/// into the same `ArtworkStyle.panel` the debug tweak panel edits.
@MainActor
@Suite(.serialized)
struct WindowStyleTests {
    /// Runs `body` with the real stored choice put back afterwards, whatever it was.
    private func preservingStoredStyle(_ body: () throws -> Void) rethrows {
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: WindowStyle.key)
        let panel = ArtworkStyle.shared.panel
        defer {
            ArtworkStyle.shared.panel = panel
            if let saved { defaults.set(saved, forKey: WindowStyle.key) } else { defaults.removeObject(forKey: WindowStyle.key) }
        }
        try body()
    }

    @Test func eachStyleMapsToItsSurface() {
        #expect(WindowStyle.glass.panelStyle == PanelStyle(surface: .glass, translucent: true))
        #expect(WindowStyle.normal.panelStyle == PanelStyle(surface: .sidebar, translucent: true))
        #expect(WindowStyle.solid.panelStyle == PanelStyle(surface: .sidebar, translucent: false))
        for style in WindowStyle.allCases {
            #expect(WindowStyle(style.panelStyle) == style)
        }
        // The tweak panel can turn translucency off under glass, which glass ignores.
        #expect(WindowStyle(PanelStyle(surface: .glass, translucent: false)) == .glass)
    }

    @Test func theDefaultIsTodaysLook() {
        #expect(WindowStyle.standard == .normal)
        #expect(WindowStyle.standard.panelStyle == PanelStyle.standard)
        #expect(PanelStyle.standard == PanelStyle(surface: .sidebar, translucent: true))
    }

    @Test func nothingStoredOrAnUnknownNameIsTheDefault() throws {
        let suite = "WindowStyleTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(WindowStyle.stored(in: defaults) == .normal)
        defaults.set("frosted", forKey: WindowStyle.key)
        #expect(WindowStyle.stored(in: defaults) == .normal)
    }

    @Test func aChoiceSurvivesARoundTrip() {
        preservingStoredStyle {
            for style in WindowStyle.allCases {
                style.store()
                #expect(WindowStyle.stored() == style)
                #expect(UserDefaults.standard.string(forKey: WindowStyle.key) == style.rawValue)
            }
        }
    }

    /// At launch the panel starts in the stored style.
    @Test func aNewStyleStartsFromTheStoredChoice() {
        preservingStoredStyle {
            WindowStyle.glass.store()
            #expect(ArtworkStyle().panel == WindowStyle.glass.panelStyle)
            WindowStyle.solid.store()
            #expect(ArtworkStyle().panel == WindowStyle.solid.panelStyle)
            UserDefaults.standard.removeObject(forKey: WindowStyle.key)
            #expect(ArtworkStyle().panel == PanelStyle.standard)
        }
    }

    /// The tweak panel and Settings both write `ArtworkStyle.panel`; every change is saved.
    @Test func editingThePanelStyleSavesIt() {
        preservingStoredStyle {
            ArtworkStyle.shared.panel = WindowStyle.glass.panelStyle
            #expect(WindowStyle.stored() == .glass)
            ArtworkStyle.shared.panel.surface = .sidebar
            ArtworkStyle.shared.panel.translucent = false
            #expect(WindowStyle.stored() == .solid)
            ArtworkStyle.shared.panel.translucent = true
            #expect(WindowStyle.stored() == .normal)
        }
    }
}
