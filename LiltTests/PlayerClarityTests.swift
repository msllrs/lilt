import Foundation
import Testing
@testable import Lilt

/// Settings ▸ Appearance ▸ Player glass: one slider from Frosted to Clear, stored as a number
/// and read back into the same `ArtworkStyle.platter.frost` the tweak panel's Frost slider edits.
@MainActor
struct PlayerClarityTests {
    private func isolatedDefaults() -> UserDefaults {
        let suite = "PlayerClarityTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    /// Clarity is frost turned around, so the tuned frost of 0.8 is where the slider starts.
    @Test func theDefaultIsTheTunedFrost() {
        #expect(abs(PlayerClarity.standard.value - 0.2) < 1e-9)
        #expect(abs(PlayerClarity.standard.frost - PlatterStyle.standard.frost) < 1e-9)
        #expect(PlatterStyle.standard(clarity: .standard) == .standard)
    }

    @Test func nothingStoredOrSomethingOddIsTheDefault() {
        let defaults = isolatedDefaults()
        #expect(PlayerClarity.stored(in: defaults) == .standard)
        defaults.set("clear", forKey: PlayerClarity.key)
        #expect(PlayerClarity.stored(in: defaults) == .standard)
    }

    @Test func aStoredClarityComesBackAndFrostsThePlatter() {
        let defaults = isolatedDefaults()
        PlayerClarity(0.64).store(in: defaults)
        let stored = PlayerClarity.stored(in: defaults)
        #expect(stored.value == 0.64)
        let platter = PlatterStyle.standard(clarity: stored)
        #expect(abs(platter.frost - 0.36) < 1e-9)
        // Only the frost moves: the glass and the colour over it are as tuned.
        var expected = PlatterStyle.standard
        expected.frost = platter.frost
        #expect(platter == expected)
    }

    /// The ends are the ends: past them is clamped, so a stray value can't over-frost or go negative.
    @Test func clarityIsClampedToTheSlider() {
        #expect(PlayerClarity(-1).value == 0)
        #expect(PlayerClarity(2).value == 1)
        #expect(PlayerClarity(frost: 1).value == 0)
        #expect(PlayerClarity(frost: 0).value == 1)
    }

    /// Settings writes through `ArtworkStyle.playerClarity`, which the platter draws from.
    @Test func settingsAndTheTweakPanelShareTheFrost() {
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: PlayerClarity.key)
        let platter = ArtworkStyle.shared.platter
        defer {
            ArtworkStyle.shared.platter = platter
            if let saved { defaults.set(saved, forKey: PlayerClarity.key) } else { defaults.removeObject(forKey: PlayerClarity.key) }
        }
        ArtworkStyle.shared.playerClarity = PlayerClarity(0.48)
        #expect(abs(ArtworkStyle.shared.platter.frost - 0.52) < 1e-9)
        #expect(PlayerClarity.stored().value == 0.48)
        ArtworkStyle.shared.platter.frost = 0.24
        #expect(abs(ArtworkStyle.shared.playerClarity.value - 0.76) < 1e-9)
    }
}
