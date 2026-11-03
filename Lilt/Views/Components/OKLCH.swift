import SwiftUI

/// A colour in OKLCH, Björn Ottosson's perceptual space in polar form: lightness `l` (0 black to
/// 1 white), chroma `c` (0 grey, about 0.3 at sRGB's most vivid) and hue `h` in degrees. Equal
/// steps look equal, so a role can keep a cover's hue and set its own lightness, which a mix
/// towards white can't: that loses chroma and lightness together and lands on a muddy mid-tone.
struct OKLCH: Equatable {
    var l: Double
    var c: Double
    var h: Double
    var opacity: Double = 1

    /// The colour resolved in `scheme` (gamma-encoded sRGB, extended values allowed).
    init(_ color: Color, in scheme: ColorScheme) {
        var environment = EnvironmentValues()
        environment.colorScheme = scheme
        let resolved = color.resolve(in: environment)
        self.init(red: Double(resolved.red), green: Double(resolved.green), blue: Double(resolved.blue), opacity: Double(resolved.opacity))
    }

    init(l: Double, c: Double, h: Double, opacity: Double = 1) {
        self.l = l
        self.c = c
        self.h = h
        self.opacity = opacity
    }

    /// From gamma-encoded sRGB.
    init(red: Double, green: Double, blue: Double, opacity: Double = 1) {
        let (r, g, b) = (Self.linear(red), Self.linear(green), Self.linear(blue))
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        let lightness = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
        let a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        let bb = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        var hue = atan2(bb, a) * 180 / .pi
        if hue < 0 { hue += 360 }
        self.init(l: lightness, c: hypot(a, bb), h: hue, opacity: opacity)
    }

    /// Linear sRGB, unclamped (out of gamut where a channel leaves 0…1).
    var linearRGB: (r: Double, g: Double, b: Double) {
        let a = c * cos(h * .pi / 180)
        let b = c * sin(h * .pi / 180)
        let l3 = pow(l + 0.3963377774 * a + 0.2158037573 * b, 3)
        let m3 = pow(l - 0.1055613458 * a - 0.0638541728 * b, 3)
        let s3 = pow(l - 0.0894841775 * a - 1.2914855480 * b, 3)
        return (
            4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3,
            -1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3,
            -0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3
        )
    }

    var isInGamut: Bool {
        let (r, g, b) = linearRGB
        let e = 1e-6
        return [r, g, b].allSatisfy { $0 >= -e && $0 <= 1 + e }
    }

    /// The same lightness and hue with chroma lowered, if need be, to the most sRGB holds: a
    /// colour sRGB can't show loses vividness rather than being clipped off its hue.
    var inGamut: OKLCH {
        var copy = self
        copy.l = min(max(l, 0), 1)
        guard !copy.isInGamut else { return copy }
        var lo = 0.0, hi = copy.c
        for _ in 0..<24 {
            copy.c = (lo + hi) / 2
            if copy.isInGamut { lo = copy.c } else { hi = copy.c }
        }
        copy.c = lo
        return copy
    }

    /// As a SwiftUI colour in sRGB (mapped into gamut first).
    var color: Color {
        let mapped = inGamut
        let (r, g, b) = mapped.linearRGB
        func encode(_ v: Double) -> Double {
            let v = min(max(v, 0), 1)
            return v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055
        }
        return Color(.sRGB, red: encode(r), green: encode(g), blue: encode(b), opacity: opacity)
    }

    private static func linear(_ v: Double) -> Double {
        v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }
}
