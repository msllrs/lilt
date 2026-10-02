import AppKit
import SwiftUI

/// Little music notes drifting up out of the playing track's disc. A `CAEmitterLayer` with
/// SF Symbol glyphs as particles (the same approach Dia's now-playing tab uses); birth rate
/// follows playback so notes stop appearing the moment you pause and the last ones fade out.
/// Every knob comes from `ArtworkStyle.shared.notes` so the tweak panel drives it live.
struct NoteEmitterView: NSViewRepresentable {
    var isPlaying: Bool
    /// The disc's centre, in the view's own unflipped coordinates (origin bottom-left).
    var center: CGPoint

    func makeNSView(context: Context) -> NoteEmitterHostView {
        let view = NoteEmitterHostView()
        view.update(isPlaying: isPlaying, center: center, style: ArtworkStyle.shared.notes)
        return view
    }

    func updateNSView(_ view: NoteEmitterHostView, context: Context) {
        view.update(isPlaying: isPlaying, center: center, style: ArtworkStyle.shared.notes)
    }
}

final class NoteEmitterHostView: NSView {
    private let emitter = CAEmitterLayer()
    private var applied: NotesStyle?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer = CALayer()
        layer?.masksToBounds = false
        emitter.emitterShape = .point
        emitter.renderMode = .unordered
        emitter.birthRate = 0
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

    func update(isPlaying: Bool, center: CGPoint, style: NotesStyle) {
        emitter.emitterPosition = CGPoint(x: center.x + style.sourceX, y: center.y + style.sourceY)
        emitter.birthRate = isPlaying ? 1 : 0
        if style != applied {
            applied = style
            emitter.emitterCells = ["music.note", "music.quarternote.3"].map { Self.cell(symbol: $0, style: style) }
            applyColor()
        }
    }

    private func applyColor() {
        guard let style = applied else { return }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let color = NSColor.labelColor.withAlphaComponent(style.opacity).cgColor
            emitter.emitterCells?.forEach { $0.color = color }
        }
    }

    /// A white symbol glyph so the cell's `color` tints it.
    private static func cell(symbol: String, style: NotesStyle) -> CAEmitterCell {
        let cell = CAEmitterCell()
        let config = NSImage.SymbolConfiguration(pointSize: style.glyphSize, weight: .semibold)
            .applying(.init(paletteColors: [.white]))
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
            var rect = NSRect(origin: .zero, size: image.size)
            cell.contents = image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
            cell.contentsScale = 2
        }
        cell.birthRate = Float(style.birthRate)
        cell.lifetime = Float(style.lifetime)
        cell.lifetimeRange = Float(style.lifetimeRange)
        cell.velocity = style.velocity
        cell.velocityRange = style.velocityRange
        cell.emissionLongitude = .pi / 2
        cell.emissionRange = style.spread
        cell.yAcceleration = style.gravity
        cell.xAcceleration = style.drift
        cell.scale = style.scale
        cell.scaleRange = style.scaleRange
        cell.scaleSpeed = style.scaleSpeed
        cell.alphaSpeed = Float(style.alphaSpeed)
        cell.spin = style.spin
        cell.spinRange = style.spinRange
        return cell
    }
}
