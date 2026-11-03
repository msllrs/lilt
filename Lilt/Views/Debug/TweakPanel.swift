#if DEBUG
import AppKit
import SwiftUI

/// Debug-only sliders for the artwork finish. Changes apply live to every artwork in the column;
/// "Copy values" puts a Swift snippet on the clipboard to paste back into `ArtworkStyle.reset()`,
/// and "Export JSON" the surface values for every window style, to paste over
/// `SurfaceDefaults.json`.
struct TweakPanel: View {
    @State private var style = ArtworkStyle.shared
    @State private var shadowContext: ArtworkContext = .player
    @State private var copied = false
    @State private var exported = false
    @State private var motion = MotionSettings.shared
    @Environment(ScrollTracker.self) private var scrollTracker
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    /// The window style on screen, whose surface values the surface dials edit.
    private var shownStyle: WindowStyle { style.shownWindowStyle(reduceTransparency: reduceTransparency) }

    var body: some View {
        @Bindable var style = style
        @Bindable var motion = motion
        Form {
            Section("Live") {
                LabeledContent("Content under platter", value: String(format: "%.0f pt", scrollTracker.activeRemainingBelow))
                LabeledContent("Active screen", value: scrollTracker.activeKey)
            }
            Section("Motion") {
                // Slows every token-built animation alike, the native frame and the disc's
                // settle included, so a frame and its content drifting apart shows in slow motion.
                slider("Animation speed", $motion.speed, MotionSettings.speedRange)
                Picker("Preset", selection: $motion.speed) {
                    ForEach([0.1, 0.25, 0.5, 1], id: \.self) { Text("\($0.formatted())×").tag($0) }
                }
                .pickerStyle(.segmented)
                // Each token's Reduce Motion variant without touching System Settings.
                Toggle("Force Reduce Motion", isOn: $motion.forcesReduceMotion)
            }
            PageTransitionSection()
            Section("Row shine") {
                // The sweep across a row after Copy Link, Play Next or Add to Queue from its menu.
                slider("Duration (s)", $style.shine.duration, 0.2...1.5)
                slider("Band width", $style.shine.band, 0.1...1)
                slider("Dark: peak (plus lighter)", $style.shine.darkOpacity, 0...0.5)
                slider("Light: peak (overlay)", $style.shine.lightOpacity, 0...1)
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
            surfaceSection
            Section("Now playing platter") {
                slider("Wash reach", $style.platter.cornerAccentRadius, 0.2...1.5)
                Picker("Wash placement", selection: $style.platter.accentPlacement) {
                    ForEach(AccentPlacement.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Cast on rim (like play capsule)", isOn: $style.platter.castEdge)
                Toggle("Cast glow inside (like play capsule)", isOn: $style.platter.castGlow)
            }
            coverPalette
            Section("Page ambient") {
                slider("Reach", $style.pageAmbient.reach, 80...800)
                slider("Cover band (h/w)", $style.pageAmbient.band, 0.2...1)
                // Past an album's tracks, onto "More from…" and the other related sections.
                Picker("On scroll", selection: $style.pageAmbient.scroll) {
                    ForEach(PageAmbientScroll.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                slider("Dim at related sections (0 none, 1 gone)", $style.pageAmbient.sectionFade, 0...1)
                slider("Dim over (pt before they reach the top)", $style.pageAmbient.sectionFadeDistance, 0...600)
                Toggle("Related section headers wear the cover", isOn: $style.pageAmbient.tintsSectionHeaders)
            }
            Section("Panel") {
                Picker("Surface", selection: $style.panel.surface) {
                    ForEach(PanelSurface.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Translucent (sidebar)", isOn: $style.panel.translucent)
            }
            Section("Hero snap (pages)") {
                Toggle("Steer flicks to an end", isOn: $style.heroSnap.enabled)
                slider("Min flick (pt/s)", $style.heroSnap.minFlick, 0...400)
                slider("Dead zone", $style.heroSnap.deadZone, 0...0.2)
            }
            Section("Library header") {
                Toggle("Centred title", isOn: $style.centredLibraryTitle)
            }
            Section("Header controls") {
                Picker("Surface", selection: $style.headerControls.mode) {
                    ForEach(HeaderControlMode.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Search field too", isOn: $style.headerControls.appliesToSearch)
                Toggle("Interactive (SwiftUI glass)", isOn: $style.headerControls.interactive)
                Toggle("AppKit: clear base", isOn: $style.headerControls.clearBase)
                intSlider("AppKit: variant", $style.headerControls.variant, HeaderControlStyle.variantRange)
                TextField("AppKit: subvariant", text: $style.headerControls.subvariant, prompt: Text("unset"))
                    .monospaced()
                Toggle("AppKit: content lensing", isOn: $style.headerControls.contentLensing)
                intSlider("AppKit: scrim", $style.headerControls.scrim, HeaderControlStyle.scrimRange)
                intSlider("AppKit: subdued", $style.headerControls.subdued, HeaderControlStyle.subduedRange)
                intSlider("AppKit: interaction", $style.headerControls.interaction, HeaderControlStyle.interactionRange)
                intSlider("AppKit: adaptive", $style.headerControls.adaptiveAppearance, HeaderControlStyle.adaptiveAppearanceRange)
                Toggle("AppKit: reduced shadow", isOn: $style.headerControls.reducedShadow)
            }
            Section("Platter glass") {
                Toggle("Always on (off: only when rows pass beneath)", isOn: $style.platter.alwaysGlass)
            }
            Section("Dock tile") {
                slider("Plate tint", $style.dockTile.plateTint, 0...0.8)
                slider("Plate saturation", $style.dockTile.plateSaturation, 0...4)
                slider("Disc shadow", $style.dockTile.shadowOpacity, 0...1)
                slider("Disc shadow blur", $style.dockTile.shadowBlur, 0...0.4)
                slider("Disc shadow offset", $style.dockTile.shadowOffsetY, -0.1...0.2)
            }
            Section("Header blur") {
                Toggle("Backdrop ramp (private API)", isOn: $style.headerBlur.useBackdrop)
                    .disabled(!ProgressiveBlurBackdrop.isAvailable)
                LabeledContent("Available", value: ProgressiveBlurBackdrop.isAvailable ? "yes" : "no")
                Toggle("Own content only (ignore windows behind)", isOn: $style.headerBlur.ownContentOnly)
            }
            Section("Play capsule cast") {
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
                    Button(exported ? "Copied" : "Export JSON") { exportSurfaces() }
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

    /// The surface values for the window style on screen in this appearance (`SurfaceMatrix`):
    /// switch the style in Settings or the appearance in System Settings to edit another cell.
    @ViewBuilder private var surfaceSection: some View {
        @Bindable var style = style
        let shown = shownStyle
        let scheme = colorScheme
        Section {
            LabeledContent("Editing", value: "\(shown.title) · \(scheme == .dark ? "Dark" : "Light")")
            slider("Platter: shadow opacity", $style.surfaces[shown, scheme].platter.shadowOpacity, 0...0.6)
            slider("Platter: shadow radius", $style.surfaces[shown, scheme].platter.shadowRadius, 0...40)
            slider("Platter: shadow offset", $style.surfaces[shown, scheme].platter.shadowOffsetY, 0...24)
            slider("Platter: border", $style.surfaces[shown, scheme].platter.borderOpacity, 0...0.4)
            slider("Platter: ambient opacity", $style.surfaces[shown, scheme].platter.tintOpacity, 0...1)
            slider("Platter: ambient saturation", $style.surfaces[shown, scheme].platter.tintSaturation, 0...8)
            slider("Platter: ambient blur", $style.surfaces[shown, scheme].platter.tintBlur, 0...300)
            slider("Platter: hover brighten", $style.surfaces[shown, scheme].platter.hoverBrightness, 0...1)
            slider("Platter: wash", $style.surfaces[shown, scheme].platter.washOpacity, 0...0.8)
            slider("Glass edge: top", $style.surfaces[shown, scheme].glassEdge.topOpacity, 0...1)
            slider("Glass edge: middle", $style.surfaces[shown, scheme].glassEdge.middleOpacity, 0...1)
            slider("Glass edge: bottom", $style.surfaces[shown, scheme].glassEdge.bottomOpacity, 0...1)
            slider("Glass edge: width", $style.surfaces[shown, scheme].glassEdge.lineWidth, 0.25...3)
            // Rex's rim: an even hairline, plus-lighter in dark and plus-darker in light.
            Toggle("Glass edge: blended hairline", isOn: $style.surfaces[shown, scheme].glassEdge.hairline)
            slider("Hairline width", $style.surfaces[shown, scheme].glassEdge.hairlineWidth, 0.25...2)
                .disabled(!style.surfaces[shown, scheme].glassEdge.hairline)
            slider("Hairline opacity", $style.surfaces[shown, scheme].glassEdge.hairlineOpacity, 0...0.3)
                .disabled(!style.surfaces[shown, scheme].glassEdge.hairline)
            slider("Header blur: radius", $style.surfaces[shown, scheme].headerBlur.radius, 0...60)
            slider("Header blur: saturation", $style.surfaces[shown, scheme].headerBlur.saturation, 0...3)
                .disabled(style.headerBlur.ownContentOnly)
            slider("Header blur: brightness", $style.surfaces[shown, scheme].headerBlur.brightness, -0.5...0.5)
            slider("Header blur: reach", $style.surfaces[shown, scheme].headerBlur.reach, 0...96)
            slider("Header blur: rim", $style.surfaces[shown, scheme].headerBlur.rimOpacity, 0...1)
            slider("Page ambient: opacity", $style.surfaces[shown, scheme].pageAmbient.opacity, 0...1)
            slider("Page ambient: saturation", $style.surfaces[shown, scheme].pageAmbient.saturation, 0...8)
            slider("Page ambient: blur", $style.surfaces[shown, scheme].pageAmbient.blur, 0...300)
            Toggle("Header controls: our lit rim", isOn: $style.surfaces[shown, scheme].headerControls.rim)
            slider("Header controls: rim opacity", $style.surfaces[shown, scheme].headerControls.rimOpacity, 0...1)
            slider("Header controls: cover tint", $style.surfaces[shown, scheme].headerControls.tintOpacity, 0...0.6)
            slider("At rest: content", $style.surfaces[shown, scheme].atRest.contentOpacity, 0.2...1)
            // The grey the page's contrast guard stands in for this panel; dark mode's ladder for
            // this style is in the dark palette section.
            slider("Palette: guard backdrop", $style.surfaces[shown, scheme].palette.guardBackdrop, 0...1)
            HStack {
                Button("Reset this cell") { style.surfaces[shown, scheme] = SurfaceMatrix.defaults[shown, scheme] }
                Spacer()
                Button(exported ? "Copied" : "Export JSON") { exportSurfaces() }
            }
        } header: {
            Text("Surface: \(shown.title) · \(scheme == .dark ? "Dark" : "Light")")
        } footer: {
            Text("Export JSON copies every style and appearance, ready to paste over Lilt/Resources/SurfaceDefaults.json.")
        }
    }

    /// One dark-mode role's lightness in the dark cell of the window style on screen.
    private func darkLightness(_ role: WritableKeyPath<SurfaceStyle.DarkLightness, Double>) -> Binding<Double> {
        let shown = shownStyle
        let style = style
        return Binding(
            get: { (style.surfaces[shown, .dark].palette.darkLightness ?? .darkPanel)[keyPath: role] },
            set: { value in
                var ladder = style.surfaces[shown, .dark].palette.darkLightness ?? .darkPanel
                ladder[keyPath: role] = value
                style.surfaces[shown, .dark].palette.darkLightness = ladder
            }
        )
    }

    /// The whole matrix on the pasteboard, as the resource file is written.
    private func exportSurfaces() {
        guard let json = try? style.surfaces.json() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(json, forType: .string)
        exported = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            exported = false
        }
    }

    /// Every surface that wears the cover reads its colours from one `CoverPalette`; these are
    /// its dials. The overrides at the end are the few a surface keeps for itself.
    @ViewBuilder private var coverPalette: some View {
        @Bindable var style = style
        Section {
            slider("Accent saturation", $style.palette.accentSaturation, 0...3)
            slider("Content share", $style.palette.contentShare, 0...1)
            slider("Dim lines (× content)", $style.palette.dimContentRatio, 0...1)
            slider("Control share", $style.palette.controlShare, 0...1)
            slider("Playing row (light)", $style.palette.highlightOpacity, 0...0.5)
            slider("Playing row (dark)", $style.palette.darkHighlightOpacity, 0...0.5)
            slider("Row hover", $style.palette.hoverHighlightOpacity, 0...1)
            slider("Control hover fill", $style.palette.controlHoverOpacity, 0...0.2)
            slider("Control pressed fill", $style.palette.controlPressedOpacity, 0...0.2)
            Toggle("Contrast guard (pages)", isOn: $style.palette.contrastGuard)
        } header: {
            Text("Cover palette")
        } footer: {
            Text("Platter, Up Next, album pages, the back button and the Window style cards. Hover and pressed fills are roles nothing draws yet. The shares are light mode's; dark mode's roles are below.")
        }
        // Dark mode's roles: the accent's hue at each role's OKLCH lightness, chroma capped. The
        // lightnesses are the window style's on screen (its surface cell), the cap every style's.
        Section {
            slider("Title lightness", darkLightness(\.primary), 0.5...1)
            slider("Control lightness", darkLightness(\.control), 0.5...1)
            slider("Secondary lightness", darkLightness(\.secondary), 0.4...1)
            slider("Tertiary lightness", darkLightness(\.tertiary), 0.3...1)
            slider("Dim control lightness", darkLightness(\.dimControl), 0.3...1)
            slider("Chroma cap", $style.palette.darkChromaCap, 0...0.3)
        } header: {
            Text("Cover palette: dark mode (OKLCH) · \(shownStyle.title)")
        } footer: {
            Text("Each role keeps the cover's hue; chroma drops further where sRGB can't hold it at that lightness. The lightnesses are this window style's (Glass can show a mid grey, so its sit higher) and go out with Export JSON. The contrast guard lifts a role that falls below its floor on a page.")
        }
        // The cast the Play capsule, its round buttons and the back button wear.
        Section {
            slider("Rim opacity", $style.leadingCast.rimOpacity, 0...1)
            slider("Rim width", $style.leadingCast.rimWidth, 0.5...3)
            slider("Rim start", $style.leadingCast.rimStart, 0...0.9)
            slider("Wash opacity", $style.leadingCast.washOpacity, 0...0.8)
            slider("Wash reach", $style.leadingCast.washReach, 0.1...1)
            slider("Dark: lightness (OKLCH)", $style.leadingCast.darkLightness, 0.4...0.95)
            slider("Dark: chroma cap", $style.leadingCast.darkChromaCap, 0...0.3)
            slider("Dark: rim opacity", $style.leadingCast.darkRimOpacity, 0...1)
            slider("Dark: wash scale", $style.leadingCast.darkWashScale, 0...2)
        } header: {
            Text("Cover palette: accent container")
        }
        // What a surface keeps for itself, and why.
        Section {
            // The cast is sampled per surface: the back button's was tuned stronger than the
            // capsule's, since it lights only a rim beside the compact header.
            slider("Back button cast saturation", $style.leadingCast.saturation, 0.5...4)
            slider("Play capsule cast saturation", $style.playCast.saturation, 0...4)
            // The scrubber is a thin line that was tuned to read at the full accent.
            Toggle("Scrubber coloured like controls", isOn: $style.platter.scrubberLikeControls)
            slider("Scrubber's own share", $style.platter.scrubberTint, 0...1)
                .disabled(style.platter.scrubberLikeControls)
        } header: {
            Text("Cover palette: per-surface overrides")
        } footer: {
            Text("The platter skips the contrast guard: it sits on its own tinted glass, not the plain panel the guard measures against.")
        }
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

    private func intSlider(_ label: String, _ value: Binding<Int>, _ range: ClosedRange<Int>) -> some View {
        LabeledContent(label) {
            HStack(spacing: Theme.Space.sm) {
                Stepper(value: value, in: range) { Text("\(value.wrappedValue)").monospacedDigit().frame(width: 28, alignment: .trailing) }
            }
        }
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
