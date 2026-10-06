import AppKit
import SwiftUI
import Testing
@testable import Lilt

/// How long a screen's worth of rows takes to build and lay out for the first time, by part,
/// so the cost of opening the library can be attributed rather than guessed at.
@MainActor
struct RowBuildTimingTests {
    private static let count = 56

    private static func seededURLs() -> [URL] {
        (0..<count).map { i in
            let url = URL(string: "https://lh3.googleusercontent.com/test-cover-\(i)=w240-h240-l90-rj")!
            if ImageCache.shared.cached(url) == nil {
                let image = NSImage(size: NSSize(width: 240, height: 240), flipped: false) { rect in
                    NSColor(hue: CGFloat(i) / CGFloat(count), saturation: 0.7, brightness: 0.8, alpha: 1).setFill()
                    rect.fill()
                    return true
                }
                ImageCache.shared.store(image, for: url)
            }
            return url
        }
    }

    private static func items(_ urls: [URL?]) -> [BrowseItem] {
        urls.enumerated().map { i, url in
            var item = BrowseItem(id: "item-\(i)", kind: .album, title: "Album Title Number \(i)", subtitle: "Album • Some Artist • 2024", artworkURL: url)
            item.artist = "Some Artist"; item.artistId = "UC-artist-\(i)"
            return item
        }
    }

    /// Hosts `content` in a window and returns the first layout's wall time in milliseconds.
    private func time(_ label: String, _ content: some View) -> Double {
        let auth = AuthService()
        let view = content
            .environment(auth)
            .environment(PlayerService(auth: auth))
            .environment(YTMusicClient(auth: auth))
            .environment(NavigationModel())
            .environment(ScrollTracker())
            .environment(CollapsedSections())
            .frame(width: 320)
        let clock = ContinuousClock()
        let start = clock.now
        let hosting = NSHostingView(rootView: AnyView(view))
        hosting.frame = NSRect(x: 0, y: 0, width: 320, height: 3000)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        let ms = Double((clock.now - start).components.attoseconds) / 1e15 + Double((clock.now - start).components.seconds) * 1000
        window.close()
        print(String(format: "AXT %-40@ %7.1f ms", label as NSString, ms))
        return ms
    }

    @Test func buildCostByPart() {
        let urls = Self.seededURLs()
        let withArt = Self.items(urls)
        let noArt = Self.items(Array(repeating: nil, count: Self.count))
        // Warm the type metadata once, then measure each part twice.
        _ = time("warm-up: BrowseRow x56 (art)", VStack(spacing: 0) { ForEach(withArt) { BrowseRow(item: $0) } })
        // The library's own shape: three folding sections in a lazy stack, in a window that shows
        // a dozen rows. Only those should be built.
        let sections = [Array(withArt[0..<24]), Array(withArt[24..<45]), Array(withArt[45..<56])]
        for _ in 0..<2 {
            _ = time("library-shaped: 3 sections, 56 rows, lazy", ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(sections.enumerated()), id: \.offset) { i, items in
                        CollapsibleSection(title: "Section \(i)", scope: "timing", items: items) { BrowseRow(item: $0) }
                    }
                }
            }.frame(height: 800))
        }
        for _ in 0..<2 {
            _ = time("text-only rows x56", VStack(spacing: 0) { ForEach(withArt) { item in HStack { Text(item.title); Spacer(); Text(item.subtitle) }.frame(height: 52) } })
            _ = time("ArtworkView x56 (art)", VStack(spacing: 0) { ForEach(withArt) { ArtworkView(url: $0.artworkURL, size: 40, radius: 8) } })
            _ = time("SpinningArtwork x56 (art)", VStack(spacing: 0) { ForEach(withArt) { SpinningArtwork(url: $0.artworkURL, size: 40, restRadius: 8, isDisc: false, isSpinning: false) } })
            _ = time("MarqueeText x112", VStack(spacing: 0) { ForEach(withArt) { item in VStack { MarqueeText(text: item.title, isActive: false); MarqueeText(text: item.subtitle, isActive: false, font: .caption) } } })
            _ = time("plain Button rows x56", VStack(spacing: 0) { ForEach(withArt) { item in Button {} label: { HStack { Text(item.title); Spacer(); Text(item.subtitle) }.frame(height: 52) }.buttonStyle(.plain) } })
            _ = time("Button rows + .help x56", VStack(spacing: 0) { ForEach(withArt) { item in Button {} label: { HStack { Text(item.title); Spacer(); Text(item.subtitle) }.frame(height: 52) }.buttonStyle(.plain).help(item.title) } })
            _ = time("Button rows + .onHover x56", VStack(spacing: 0) { ForEach(withArt) { item in Button {} label: { HStack { Text(item.title); Spacer(); Text(item.subtitle) }.frame(height: 52) }.buttonStyle(.plain).onHover { _ in } } })
            _ = time("two nested Buttons x56", VStack(spacing: 0) { ForEach(withArt) { item in Button {} label: { HStack { Button {} label: { Text("A") }.buttonStyle(.plain); Text(item.title); Spacer() }.frame(height: 52) }.buttonStyle(.plain) } })
            _ = time("ArtistLink x56", VStack(spacing: 0) { ForEach(withArt) { ArtistLink(name: "Some Artist", item: $0.artistItem) } })
            _ = time("BrowseRow x56 (no art)", VStack(spacing: 0) { ForEach(noArt) { BrowseRow(item: $0) } })
            _ = time("BrowseRow x56 (art)", VStack(spacing: 0) { ForEach(withArt) { BrowseRow(item: $0) } })
        }
    }
}
