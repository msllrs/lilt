import AppKit
import SwiftUI

/// Little music notes drifting up out of the playing track's disc. A `CAEmitterLayer` with
/// SF Symbol glyphs as particles (the same approach Dia's now-playing tab uses); birth rate
/// follows playback so notes stop appearing the moment you pause and the last ones fade out.
struct NoteEmitterView: NSViewRepresentable {
    var isPlaying: Bool
    /// Where notes come from, in the view's own unflipped coordinates (origin bottom-left).
    var source: CGPoint

    func makeNSView(context: Context) -> NoteEmitterHostView {
        let view = NoteEmitterHostView()
        view.update(isPlaying: isPlaying, source: source)
        return view
    }

    func updateNSView(_ view: NoteEmitterHostView, context: Context) {
        view.update(isPlaying: isPlaying, source: source)
    }
}

final class NoteEmitterHostView: NSView {
    private let emitter = CAEmitterLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer = CALayer()
        layer?.masksToBounds = false
        emitter.emitterShape = .point
        emitter.renderMode = .unordered
        emitter.birthRate = 0
        emitter.emitterCells = ["music.note", "music.quarternote.3"].map(Self.cell(symbol:))
        layer?.addSublayer(emitter)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        emitter.frame = bounds
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColor()
    }

    func update(isPlaying: Bool, source: CGPoint) {
        emitter.emitterPosition = source
        emitter.birthRate = isPlaying ? 1 : 0
        applyColor()
    }

    private func applyColor() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let color = NSColor.labelColor.withAlphaComponent(0.85).cgColor
            emitter.emitterCells?.forEach { $0.color = color }
        }
    }

    /// A white symbol glyph so the cell's `color` tints it.
    private static func cell(symbol: String) -> CAEmitterCell {
        let cell = CAEmitterCell()
        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            .applying(.init(paletteColors: [.white]))
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
            var rect = NSRect(origin: .zero, size: image.size)
            cell.contents = image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
            cell.contentsScale = 2
        }
        cell.birthRate = 0.9
        cell.lifetime = 1.9
        cell.lifetimeRange = 0.4
        cell.velocity = 16
        cell.velocityRange = 6
        cell.emissionLongitude = .pi / 2          // up
        cell.emissionRange = .pi / 5
        cell.yAcceleration = 6
        cell.xAcceleration = 0
        cell.scale = 0.55
        cell.scaleRange = 0.15
        cell.scaleSpeed = -0.08
        cell.alphaSpeed = -0.5
        cell.spin = 0.4
        cell.spinRange = 0.8
        return cell
    }
}
