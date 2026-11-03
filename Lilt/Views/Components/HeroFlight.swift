import AppKit
import SwiftUI

/// The hero morph (tweak panel ▸ Page transition ▸ Hero morph): a tapped row's cover flies to
/// the page's hero cover, and on pop back to the row if it's still on screen.
///
/// Not `matchedGeometryEffect`: the row sits in a page that is parked (faded to nothing) the
/// moment the new page arrives, both ends are clipped by their scroll views, and both exist at
/// once. Instead a ghost of the cover is drawn over the column, above every page, from one
/// frame to the other, while the real cover and hero hide; the hero shows again as the ghost
/// lands on it. Frames are in each page's own coordinate space (`PageSpace`), which is the
/// column's while the page is in its place.
@MainActor
@Observable
final class HeroFlight {
    static let shared = HeroFlight()

    /// The cover a page was opened from.
    struct Source: Equatable {
        /// The screen the row is on (`PageSpace.key`).
        var screen: String
        var frame: CGRect
        var radius: CGFloat
        var url: URL?
    }

    struct Flight: Equatable, Identifiable {
        let id: Int
        /// The page whose hero is flown to (push) or from (pop).
        let page: String
        /// The screen whose row is flown from (push) or to (pop).
        let sourceScreen: String
        let from: CGRect
        var to: CGRect?
        let fromRadius: CGFloat
        var toRadius: CGFloat
        let url: URL?
        let isPop: Bool
    }

    /// The flight in the air, if any. The only observed state: the ghost draws it, and the row
    /// and hero it stands in for hide while it flies.
    private(set) var flight: Flight?

    /// Not observed: written as rows are tapped and heroes laid out.
    @ObservationIgnored private var sources: [String: Source] = [:]
    @ObservationIgnored private var heroes: [String: (frame: CGRect, radius: CGFloat)] = [:]
    @ObservationIgnored private var nextID = 0

    func hidesHero(of page: String) -> Bool { flight?.page == page }
    func hidesSource(_ item: String, on screen: String) -> Bool { flight?.page == item && flight?.sourceScreen == screen }

    /// A row was tapped to open `item`: remember where its cover is, for the flight there and
    /// back, and set off if the page is new to the stack. The flight waits on the hero's frame.
    func tapped(_ item: BrowseItem, on screen: String, frame: CGRect, radius: CGFloat, path: [BrowseItem]) {
        guard frame.width > 0 else { return }
        let source = Source(screen: screen, frame: frame, radius: radius, url: item.artworkURL)
        sources[item.id] = source
        guard !path.contains(where: { $0.id == item.id }), path.last?.id ?? PageSpace.searchKey == screen else { return }
        nextID += 1
        let id = nextID
        flight = Flight(id: id, page: item.id, sourceScreen: screen, from: frame, to: nil, fromRadius: radius, toRadius: radius, url: item.artworkURL, isPop: false)
        // A page whose hero never lays out (it failed, or has none) lets the row go.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.5))
            if self.flight?.id == id, self.flight?.to == nil { self.flight = nil }
        }
    }

    /// The hero cover of `page` is at `frame`: the push flight waiting on it can take off.
    func heroLaidOut(_ page: String, frame: CGRect, radius: CGFloat) {
        heroes[page] = (frame, radius)
        if var flight, flight.page == page, !flight.isPop, flight.to == nil, frame.width > 0 {
            flight.to = frame
            flight.toRadius = radius
            self.flight = flight
        }
    }

    /// The stack changed from `old` to `new`. A flight that isn't this change's own is cut
    /// short (everything shows again at once); a pop flies the hero back to the row it was
    /// opened from when both are on screen in `bounds` (the column, below the header).
    func pathChanged(from old: [BrowseItem], to new: [BrowseItem], bounds: CGRect) {
        if let flight, flight.isPop || new.last?.id != flight.page { self.flight = nil }
        guard case .pop = PageMove.between(old.map(\.id), new.map(\.id)), let top = old.last,
              let source = sources[top.id], let hero = heroes[top.id] else { return }
        let revealed = new.last?.id ?? PageSpace.searchKey
        guard source.screen == revealed, bounds.contains(source.frame), bounds.contains(hero.frame) else { return }
        nextID += 1
        flight = Flight(id: nextID, page: top.id, sourceScreen: source.screen, from: hero.frame, to: source.frame, fromRadius: hero.radius, toRadius: source.radius, url: source.url, isPop: true)
    }

    /// The ghost has landed: the real cover takes over.
    func landed(_ id: Int) {
        if flight?.id == id { flight = nil }
    }

    func cancel() { flight = nil }
}

/// The coordinate space each staged page lays out in: the column's own while the page is in
/// its place, unmoved by its transition's offsets.
enum PageSpace {
    static let name = "liltPage"
    static let searchKey = "search"
}

extension EnvironmentValues {
    /// Which screen of the stack this is: `PageSpace.searchKey` or the page's id.
    @Entry var pageKey: String = PageSpace.searchKey
    /// The hero morph is on: rows note where their covers are, heroes where they land.
    @Entry var heroTracking: Bool = false
}

/// Where a row's cover is, kept without invalidating anything as it changes.
@MainActor
final class HeroFrameBox {
    var frame: CGRect = .zero
}

/// A row's cover: measured while the pointer is over it (so a scroll costs nothing), and hidden
/// while its ghost flies.
private struct HeroSourceSlot: ViewModifier {
    let item: String
    let isHovering: Bool
    let box: HeroFrameBox
    @Environment(\.heroTracking) private var tracking
    @Environment(\.pageKey) private var screen

    func body(content: Content) -> some View {
        let hidden = tracking && HeroFlight.shared.hidesSource(item, on: screen)
        let measuring = tracking && isHovering
        content
            .opacity(hidden ? 0 : 1)
            .onGeometryChange(for: CGRect.self) { measuring ? $0.frame(in: .named(PageSpace.name)) : .zero } action: { frame in
                if frame != .zero { box.frame = frame }
            }
    }
}

/// A page's hero cover: reports where it lies, and hides while a ghost flies to or from it.
private struct HeroTargetSlot: ViewModifier {
    let page: String
    let radius: CGFloat
    @Environment(\.heroTracking) private var tracking

    func body(content: Content) -> some View {
        let hidden = tracking && HeroFlight.shared.hidesHero(of: page)
        content
            .opacity(hidden ? 0 : 1)
            .onGeometryChange(for: CGRect.self) { tracking ? $0.frame(in: .named(PageSpace.name)) : .zero } action: { frame in
                if frame != .zero { HeroFlight.shared.heroLaidOut(page, frame: frame, radius: radius) }
            }
    }
}

extension View {
    func heroSource(_ item: String, isHovering: Bool, box: HeroFrameBox) -> some View {
        modifier(HeroSourceSlot(item: item, isHovering: isHovering, box: box))
    }

    func heroTarget(_ page: String, radius: CGFloat) -> some View {
        modifier(HeroTargetSlot(page: page, radius: radius))
    }
}

/// The ghost in flight, drawn over the column. It sets off as soon as it knows where it's
/// going, along the choreography's flight phase, and hands over as it lands.
struct HeroGhost: View {
    let flight: HeroFlight.Flight
    let phase: PagePhase
    @State private var landed = false

    var body: some View {
        let image = flight.url.flatMap { ImageCache.shared.cached($0) ?? ImageCache.shared.anyVariant(for: $0) }
        GhostFrame(progress: landed ? 1 : 0, from: flight.from, to: flight.to ?? flight.from, fromRadius: flight.fromRadius, toRadius: flight.toRadius, image: image)
            .allowsHitTesting(false)
            .onAppear { if flight.to != nil { launch() } }
            .onChange(of: flight.to) { _, to in if to != nil, !landed { launch() } }
    }

    private func launch() {
        let id = flight.id
        withAnimation(phase.animation, completionCriteria: .logicallyComplete) {
            landed = true
        } completion: {
            HeroFlight.shared.landed(id)
        }
    }
}

/// The ghost's frame and corner part way between the two ends, so a flight interrupted or
/// retargeted carries on from where it is.
nonisolated private struct GhostFrame: View, Animatable {
    var progress: Double
    let from: CGRect
    let to: CGRect
    let fromRadius: CGFloat
    let toRadius: CGFloat
    let image: NSImage?

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let t = CGFloat(progress)
        let mix = { (a: CGFloat, b: CGFloat) -> CGFloat in a + (b - a) * t }
        let rect = CGRect(x: mix(from.minX, to.minX), y: mix(from.minY, to.minY), width: mix(from.width, to.width), height: mix(from.height, to.height))
        let shape = RoundedRectangle(cornerRadius: mix(fromRadius, toRadius), style: .continuous)
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Color.secondary.opacity(0.2)
            }
        }
        .frame(width: rect.width, height: rect.height)
        .clipShape(shape)
        .position(x: rect.midX, y: rect.midY)
    }
}
