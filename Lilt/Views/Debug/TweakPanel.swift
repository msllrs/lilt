#if DEBUG
import AppKit
import SwiftUI

/// Debug-only sliders for the artwork finish. Changes apply live to every artwork in the column;
/// "Copy values" puts a Swift snippet on the clipboard to paste back into `ArtworkStyle.reset()`.
struct TweakPanel: View {
    @State private var style = ArtworkStyle.shared
    @State private var shadowContext: ArtworkContext = .player
    @State private var copied = false
    @Environment(ScrollTracker.self) private var scrollTracker

    var body: some View {
        @Bindable var style = style
        Form {
            Section("Live") {
                LabeledContent("Content under platter", value: String(format: "%.0f pt", scrollTracker.activeRemainingBelow))
                LabeledContent("Active screen", value: scrollTracker.activeKey)
            }
            Section("Spotlight") {
                slider("Centre X", $style.spotlightCenterX, 0...1)
                slider("Centre Y", $style.spotlightCenterY, -0.5...1)
                slider("Radius", $style.spotlightRadius, 0.2...2)
                slider("Opacity", $style.spotlightOpacity, 0...0.8)
                Picker("Blend", selection: $style.spotlightBlend) {
                    ForEach(ArtworkBlend.allCases) { Text($0.rawValue).tag($0) }
                }
            }
            Section("Keyline") {
                Picker("Mode", selection: $style.keylineMode) {
                    ForEach(KeylineMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                slider("Width (px)", $style.keylineWidth, 0...3)
                slider("Dark opacity", $style.keylineDarkOpacity, 0...0.4)
                slider("Light opacity", $style.keylineLightOpacity, 0...0.4)
                slider("Light/dark threshold", $style.keylineThreshold, 0...1)
                slider("Outer separator", $style.separatorOpacity, 0...0.5)
                slider("Dark: keyline (white)", $style.darkKeylineOpacity, 0...0.6)
                slider("Dark: separator", $style.darkSeparatorOpacity, 0...0.6)
            }
            Section("Ambient shadow") {
                Picker("For", selection: $shadowContext) {
                    ForEach(ArtworkContext.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                slider("Opacity", shadow(\.opacity), 0...1)
                slider("Blur", shadow(\.blur), 0...0.5)
                slider("Offset Y", shadow(\.offsetY), -0.2...0.4)
                slider("Spread", shadow(\.spread), 0.5...1.2)
                slider("Saturation", shadow(\.saturation), 0...6)
                slider("Light comp.", shadow(\.lightCompensation), 0...1)
                slider("Neutral base", shadow(\.baseOpacity), 0...0.6)
            }
            Section("Now playing platter") {
                slider("Shadow opacity", $style.platter.shadowOpacity, 0...0.6)
                slider("Shadow radius", $style.platter.shadowRadius, 0...40)
                slider("Shadow offset", $style.platter.shadowOffsetY, 0...24)
                slider("Border", $style.platter.borderOpacity, 0...0.4)
                slider("Ambient opacity", $style.platter.tintOpacity, 0...1)
                slider("Ambient saturation", $style.platter.tintSaturation, 0...8)
                slider("Ambient blur", $style.platter.tintBlur, 0...300)
                slider("Hover brighten", $style.platter.hoverBrightness, 0...1)
                slider("Corner accent", $style.platter.cornerAccentOpacity, 0...0.8)
                slider("Corner reach", $style.platter.cornerAccentRadius, 0.2...1.5)
                slider("Scrubber tint", $style.platter.scrubberTint, 0...1)
                slider("Scrubber saturation", $style.platter.scrubberSaturation, 0...3)
                slider("Controls tint", $style.platter.controlsTint, 0...1)
            }
            Section("Header blur") {
                Toggle("Backdrop ramp (private API)", isOn: $style.headerBlur.useBackdrop)
                    .disabled(!ProgressiveBlurBackdrop.isAvailable)
                LabeledContent("Available", value: ProgressiveBlurBackdrop.isAvailable ? "yes" : "no")
                slider("Radius", $style.headerBlur.radius, 0...60)
                slider("Saturation", $style.headerBlur.saturation, 0...3)
                slider("Brightness", $style.headerBlur.brightness, -0.5...0.5)
                slider("Reach", $style.headerBlur.reach, 0...96)
            }
            Section("Play capsule cast") {
                slider("Saturation", $style.playCast.saturation, 0...4)
                slider("Glass tint", $style.playCast.tintOpacity, 0...0.6)
                slider("Rim colour", $style.playCast.rimMix, 0...1)
                slider("Glow opacity", $style.playCast.glowOpacity, 0...1)
                slider("Glow blur", $style.playCast.glowBlur, 0...40)
                slider("Glow height", $style.playCast.glowHeight, 0.05...1)
                slider("Rim blur", $style.playCast.rimBlur, 0...8)
                Picker("Rim blend", selection: $style.playCast.rimBlend) {
                    ForEach(ArtworkBlend.allCases) { Text($0.rawValue).tag($0) }
                }
            }
            Section("Music notes") {
                Picker("Colour", selection: $style.notes.colorMode) {
                    ForEach(NoteColorMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                slider("Hue period", $style.notes.huePeriod, 1...30)
                slider("Sway", $style.notes.sway, 0...1.2)
                slider("Sway period", $style.notes.swayPeriod, 0.5...10)
                slider("Rate (per sec)", $style.notes.birthRate, 0...6)
                slider("Lifetime", $style.notes.lifetime, 0.3...5)
                slider("Lifetime random", $style.notes.lifetimeRange, 0...3)
                slider("Speed", $style.notes.velocity, 0...80)
                slider("Speed random", $style.notes.velocityRange, 0...40)
                slider("Spread", $style.notes.spread, 0...Double.pi)
                slider("Rise", $style.notes.gravity, -40...40)
                slider("Drift", $style.notes.drift, -40...40)
                slider("Drift random", $style.notes.driftRange, 0...40)
                slider("Glyph size", $style.notes.glyphSize, 6...24)
                slider("Scale", $style.notes.scale, 0.1...1.5)
                slider("Scale random", $style.notes.scaleRange, 0...1)
                slider("Shrink", $style.notes.scaleSpeed, -0.6...0.4)
                slider("Fade", $style.notes.alphaSpeed, -2...0)
                slider("Opacity", $style.notes.opacity, 0...1)
                slider("Spin", $style.notes.spin, -3...3)
                slider("Spin random", $style.notes.spinRange, 0...4)
                slider("Source X", $style.notes.sourceX, -30...30)
                slider("Source Y", $style.notes.sourceY, -30...40)
            }
            Section {
                HStack {
                    Button("Reset") { style.reset() }
                    Spacer()
                    Button(copied ? "Copied" : "Copy values") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(style.swiftSnippet, forType: .string)
                        copied = true
                        Task {
                            try? await Task.sleep(for: .seconds(1.5))
                            copied = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 360, height: 900)
    }

    /// A binding into the shadow preset currently selected in the segmented control.
    private func shadow(_ keyPath: WritableKeyPath<ShadowStyle, Double>) -> Binding<Double> {
        Binding(
            get: { style.shadow(for: shadowContext)[keyPath: keyPath] },
            set: { value in
                var shadow = style.shadow(for: shadowContext)
                shadow[keyPath: keyPath] = value
                style.setShadow(shadow, for: shadowContext)
            }
        )
    }

    private func slider(_ label: String, _ value: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
        LabeledContent(label) {
            HStack(spacing: Theme.Space.sm) {
                Slider(value: value, in: range)
                Text(String(format: "%.2f", value.wrappedValue))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)
            }
        }
    }
}
#endif
