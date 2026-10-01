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
                slider("Outer separator", $style.separatorOpacity, 0...0.2)
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
        .frame(width: 360, height: 860)
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
