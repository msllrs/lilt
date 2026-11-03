import Foundation
import SwiftUI
import Testing
@testable import Lilt

/// The hero morph's bookkeeping: a tapped row's cover sets off for the page's hero once that
/// has laid out, a pop flies back only when the row and the hero are both on screen, and any
/// other navigation mid-flight cuts it short so nothing stays hidden.
@MainActor
struct HeroFlightTests {
    private let album = BrowseItem(id: "MPREb_hero", kind: .album, title: "Lateralus", subtitle: "Tool", artworkURL: URL(string: "https://example.com/cover.jpg"))
    private let other = BrowseItem(id: "MPREb_other", kind: .album, title: "Fear Inoculum", subtitle: "Tool", artworkURL: nil)
    private let row = CGRect(x: 20, y: 200, width: 40, height: 40)
    private let hero = CGRect(x: 90, y: 72, width: 140, height: 140)
    private let column = CGRect(x: 0, y: 64, width: 320, height: 600)

    @Test func aTappedRowFliesToTheHeroOnceItHasLaidOut() {
        let flights = HeroFlight()
        flights.tapped(album, on: PageSpace.searchKey, frame: row, radius: 8, path: [])
        // In the air already, waiting on where it's going; the row's cover hides.
        #expect(flights.flight?.from == row && flights.flight?.to == nil)
        #expect(flights.hidesSource(album.id, on: PageSpace.searchKey))
        #expect(flights.hidesHero(of: album.id))
        #expect(!flights.hidesSource(album.id, on: other.id))

        flights.pathChanged(from: [], to: [album], bounds: column)
        #expect(flights.flight != nil, "the push this flight belongs to cut it short")
        flights.heroLaidOut(album.id, frame: hero, radius: 16)
        #expect(flights.flight?.to == hero && flights.flight?.toRadius == 16)

        flights.landed(flights.flight!.id)
        #expect(flights.flight == nil)
        #expect(!flights.hidesHero(of: album.id))
    }

    @Test func aPageAlreadyOnTheStackDoesntFly() {
        let flights = HeroFlight()
        flights.tapped(album, on: other.id, frame: row, radius: 8, path: [album, other])
        #expect(flights.flight == nil)
    }

    @Test func popFliesBackToTheRowWhileItsOnScreen() {
        let flights = HeroFlight()
        flights.tapped(album, on: PageSpace.searchKey, frame: row, radius: 8, path: [])
        flights.pathChanged(from: [], to: [album], bounds: column)
        flights.heroLaidOut(album.id, frame: hero, radius: 16)
        flights.landed(flights.flight!.id)

        flights.pathChanged(from: [album], to: [], bounds: column)
        let back = flights.flight
        #expect(back?.isPop == true)
        #expect(back?.from == hero && back?.to == row)
        #expect(back?.fromRadius == 16 && back?.toRadius == 8)
        #expect(flights.hidesSource(album.id, on: PageSpace.searchKey) && flights.hidesHero(of: album.id))
    }

    @Test func popFadesWhenTheRowOrTheHeroIsOutOfSight() {
        let flights = HeroFlight()
        flights.tapped(album, on: PageSpace.searchKey, frame: row, radius: 8, path: [])
        flights.heroLaidOut(album.id, frame: hero, radius: 16)
        flights.landed(flights.flight!.id)
        // The hero scrolled away under the header.
        flights.heroLaidOut(album.id, frame: hero.offsetBy(dx: 0, dy: -200), radius: 16)
        flights.pathChanged(from: [album], to: [], bounds: column)
        #expect(flights.flight == nil)

        // The row now off the bottom (the window was resized).
        flights.heroLaidOut(album.id, frame: hero, radius: 16)
        flights.pathChanged(from: [album], to: [], bounds: CGRect(x: 0, y: 64, width: 320, height: 100))
        #expect(flights.flight == nil)
    }

    /// Popping past the page the row was on, to the root, fades: that row isn't on the screen
    /// revealed.
    @Test func popToRootFliesOnlyFromThePageOpenedThere() {
        let flights = HeroFlight()
        flights.tapped(other, on: album.id, frame: row, radius: 8, path: [album])
        flights.heroLaidOut(other.id, frame: hero, radius: 16)
        flights.landed(flights.flight!.id)
        flights.pathChanged(from: [album, other], to: [], bounds: column)
        #expect(flights.flight == nil)
    }

    /// Clicking again mid-flight (back, or another row) shows everything at once rather than
    /// leaving a cover hidden.
    @Test func anotherNavigationMidFlightCutsItShort() {
        let flights = HeroFlight()
        flights.tapped(album, on: PageSpace.searchKey, frame: row, radius: 8, path: [])
        flights.pathChanged(from: [], to: [album], bounds: column)
        flights.heroLaidOut(album.id, frame: hero, radius: 16)
        let first = flights.flight!.id
        flights.pathChanged(from: [album], to: [], bounds: column)
        // Back mid-push: the push flight is gone (a pop flight may replace it).
        #expect(flights.flight?.id != first)
        flights.pathChanged(from: [], to: [other], bounds: column)
        #expect(flights.flight == nil)
        #expect(!flights.hidesHero(of: album.id) && !flights.hidesSource(album.id, on: PageSpace.searchKey))
        // A late landing from the flight cut short changes nothing.
        flights.landed(first)
        #expect(flights.flight == nil)
    }

    @Test func aHeroThatNeverLaysOutLetsTheRowGo() async throws {
        let flights = HeroFlight()
        flights.tapped(album, on: PageSpace.searchKey, frame: row, radius: 8, path: [])
        #expect(flights.flight != nil)
        try await Task.sleep(for: .seconds(0.6))
        #expect(flights.flight == nil)
    }
}
