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
    /// For the artwork colour mode.
    var artworkURL: URL?
    /// Scales the notes to the disc they rise from (1 is the row's 40pt disc): glyph size, speed,
    /// drift and the source offset all scale together.
    var scale: CGFloat = 1
    @Environment(\.screenIsParked) private var parked

    func makeNSView(context: Context) -> NoteEmitterHostView {
        let view = NoteEmitterHostView()
        view.update(isPlaying: isPlaying && !parked, center: center, artworkURL: artworkURL, style: ArtworkStyle.shared.notes.scaled(scale))
        return view
    }

    func updateNSView(_ view: NoteEmitterHostView, context: Context) {
        view.update(isPlaying: isPlaying && !parked, center: center, artworkURL: artworkURL, style: ArtworkStyle.shared.notes.scaled(scale))
    }
}

extension NotesStyle {
    /// The same notes for a disc `factor` times the row's size.
    func scaled(_ factor: CGFloat) -> NotesStyle {
        guard factor != 1 else { return self }
        var s = self
        let f = Double(factor)
        s.velocity *= f; s.velocityRange *= f; s.gravity *= f; s.drift *= f; s.driftRange *= f
        s.glyphSize *= f; s.sourceX *= f; s.sourceY *= f
        return s
    }
}

final class NoteEmitterHostView: NSView {
    private let emitter = CAEmitterLayer()
    private var applied: NotesStyle?
    private var artworkURL: URL?
    private var cellNames: [String] = []

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

    @MainActor
    func update(isPlaying: Bool, center: CGPoint, artworkURL: URL?, style: NotesStyle) {
        emitter.emitterPosition = CGPoint(x: center.x + style.sourceX, y: center.y + style.sourceY)
        emitter.birthRate = isPlaying ? 1 : 0
        let artworkChanged = artworkURL != self.artworkURL
        self.artworkURL = artworkURL
        if style != applied {
            applied = style
            rebuildCells(style)
            applyMotion(style)
            applyColor()
        } else if artworkChanged, style.colorMode == .artwork {
            applyColor()
        }
    }

    private func rebuildCells(_ style: NotesStyle) {
        // Core Animation has no random range for acceleration, so vary drift by spawning from
        // several cells spread across the range, each with a share of the birth rate.
        let drifts: [Double] = style.driftRange > 0
            ? [-1, -0.5, 0, 0.5, 1].map { style.drift + $0 * style.driftRange }
            : [style.drift]
        var names: [String] = []
        var cells: [CAEmitterCell] = []
        for (s, symbol) in ["music.note", "music.quarternote.3"].enumerated() {
            for (d, drift) in drifts.enumerated() {
                let cell = Self.cell(symbol: symbol, style: style, drift: drift, share: 1 / Double(drifts.count))
                cell.name = "c\(s)_\(d)"
                names.append(cell.name!)
                cells.append(cell)
            }
        }
        cellNames = names
        emitter.emitterCells = cells
    }

    /// Sway: swing every cell's emission angle either side of straight up. Hue drift: walk the
    /// particle colour around the wheel. Both are animations on the emitter's cell key paths.
    private func applyMotion(_ style: NotesStyle) {
        emitter.removeAllAnimations()
        for name in cellNames {
            if style.sway > 0 {
                let swing = CABasicAnimation(keyPath: "emitterCells.\(name).emissionLongitude")
                swing.fromValue = Double.pi / 2 - style.sway
                swing.toValue = Double.pi / 2 + style.sway
                swing.duration = max(style.swayPeriod, 0.2) / 2
                swing.autoreverses = true
                swing.repeatCount = .infinity
                swing.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                emitter.add(swing, forKey: "sway-\(name)")
            }
            if style.colorMode == .hueDrift {
                let hues = CAKeyframeAnimation(keyPath: "emitterCells.\(name).color")
                hues.values = stride(from: 0.0, through: 1.0, by: 1.0 / 12).map {
                    NSColor(calibratedHue: $0, saturation: 0.75, brightness: 0.95, alpha: style.opacity).cgColor
                }
                hues.duration = max(style.huePeriod, 0.5)
                hues.repeatCount = .infinity
                hues.calculationMode = .linear
                emitter.add(hues, forKey: "hue-\(name)")
            }
        }
    }

    @MainActor
    private func applyColor() {
        guard let style = applied else { return }
        let color: CGColor
        switch style.colorMode {
        case .artwork:
            let tint = artworkURL.flatMap { ImageCache.shared.tint(for: $0, saturationBoost: 1.8) }
            color = (tint.map { NSColor($0) } ?? NSColor.labelColor).withAlphaComponent(style.opacity).cgColor
        case .label, .hueDrift:
            var resolved = NSColor.labelColor.withAlphaComponent(style.opacity).cgColor
            effectiveAppearance.performAsCurrentDrawingAppearance {
                resolved = NSColor.labelColor.withAlphaComponent(style.opacity).cgColor
            }
            color = resolved
        }
        emitter.emitterCells?.forEach { $0.color = color }
    }

    /// A white symbol glyph so the cell's `color` tints it.
    private static func cell(symbol: String, style: NotesStyle, drift: Double, share: Double) -> CAEmitterCell {
        let cell = CAEmitterCell()
        let config = NSImage.SymbolConfiguration(pointSize: style.glyphSize, weight: .semibold)
            .applying(.init(paletteColors: [.white]))
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
            var rect = NSRect(origin: .zero, size: image.size)
            cell.contents = image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
            cell.contentsScale = 2
        }
        cell.birthRate = Float(style.birthRate * share)
        cell.lifetime = Float(style.lifetime)
        cell.lifetimeRange = Float(style.lifetimeRange)
        cell.velocity = style.velocity
        cell.velocityRange = style.velocityRange
        cell.emissionLongitude = .pi / 2
        cell.emissionRange = style.spread
        cell.yAcceleration = style.gravity
        cell.xAcceleration = drift
        cell.scale = style.scale
        cell.scaleRange = style.scaleRange
        cell.scaleSpeed = style.scaleSpeed
        cell.alphaSpeed = Float(style.alphaSpeed)
        cell.spin = style.spin
        cell.spinRange = style.spinRange
        return cell
    }
}
