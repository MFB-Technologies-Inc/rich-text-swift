// HTMLColor.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation

enum HTMLColor {
    /// Parses a CSS color value: hex, `rgb()`/`rgba()`, `hsl()`/`hsla()` (comma
    /// or space syntax, `/` alpha, percentages), and every CSS named color. A
    /// trailing `!important` is ignored.
    ///
    /// Returns `nil` for anything unrecognized (`inherit`, `windowtext`, …) so
    /// the caller falls back to the inherited color. A color that is mostly or
    /// fully transparent (alpha < 0.5, `transparent`) parses to
    /// `RichTextColor.black` — the model's "no color" — rather than `nil`: it
    /// is a recognized request for no visible color, and so should clear an
    /// inherited one the way black does. Alpha ≥ 0.5 is dropped, not
    /// composited: there is no known background to blend against.
    static func parse(_ raw: String) -> RichTextColor? {
        var text = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if text.hasSuffix("!important") {
            text = String(text.dropLast("!important".count)).trimmingCharacters(in: .whitespaces)
        }
        if text.isEmpty {
            return nil
        }
        if text.hasPrefix("#") {
            return RichTextColor(hex: text)
        }
        if text == "transparent" {
            return .black
        }
        if text.hasPrefix("rgb") {
            return parseFunction(text, hsl: false)
        }
        if text.hasPrefix("hsl") {
            return parseFunction(text, hsl: true)
        }
        if let hex = named[text] {
            return RichTextColor(hex: hex)
        }
        return nil
    }

    /// The effective `color` of an inline `style` attribute, following the CSS
    /// cascade within one declaration block: the last parseable declaration
    /// wins, except that an `!important` one beats any later normal one.
    /// Unparseable declarations are skipped, as a browser drops invalid ones.
    static func colorFromStyle(_ style: String) -> RichTextColor? {
        var result: RichTextColor?
        var resultIsImportant = false
        for decl in style.split(separator: ";") {
            let pair = decl.split(separator: ":", maxSplits: 1)
            guard pair.count == 2,
                  pair[0].trimmingCharacters(in: .whitespaces).lowercased() == "color",
                  let color = parse(String(pair[1]))
            else { continue }
            let important = pair[1].lowercased().contains("!important")
            if important || !resultIsImportant {
                result = color
                resultIsImportant = important
            }
        }
        return result
    }

    // MARK: - Functional notation

    /// `rgb[a](…)` / `hsl[a](…)`. Accepts `r, g, b[, a]`, `r g b[ / a]`, and
    /// the legacy `r, g, b / a` mix; `rgb` and `rgba` are aliases (as in CSS
    /// Color 4), likewise `hsl`/`hsla`.
    private static func parseFunction(_ text: String, hsl: Bool) -> RichTextColor? {
        guard let (parts, alphaToken) = splitArguments(text) else { return nil }

        if let alphaToken {
            guard let alpha = unit(alphaToken, scale: 1) else { return nil }
            if alpha < 0.5 {
                return .black
            }
        }

        if hsl {
            guard let hueDegrees = hue(parts[0]),
                  let saturation = unit(parts[1], scale: 100),
                  let lightness = unit(parts[2], scale: 100)
            else { return nil }
            return fromHSL(hueDegrees, saturation, lightness)
        }
        guard let red = unit(parts[0], scale: 255),
              let green = unit(parts[1], scale: 255),
              let blue = unit(parts[2], scale: 255)
        else { return nil }
        return RichTextColor(red: byte(red), green: byte(green), blue: byte(blue))
    }

    /// Splits the arguments of `rgb[a](…)`/`hsl[a](…)` into exactly three
    /// component tokens plus an optional alpha token, accepting the comma,
    /// space, and `/` syntaxes. Returns `nil` if the shape is not recognized.
    private static func splitArguments(_ text: String) -> (parts: [String], alpha: String?)? {
        guard let open = text.firstIndex(of: "("), let close = text.firstIndex(of: ")"), open < close
        else { return nil }
        let inner = text[text.index(after: open) ..< close]
        let halves = inner.split(separator: "/", omittingEmptySubsequences: false)
        guard halves.count <= 2 else { return nil }
        var parts = halves[0]
            .split(whereSeparator: { $0 == "," || $0.isWhitespace })
            .map(String.init)
        var alphaToken: String?
        if halves.count == 2 {
            alphaToken = halves[1].trimmingCharacters(in: .whitespaces)
        } else if parts.count == 4 {
            alphaToken = parts.removeLast()
        }
        guard parts.count == 3 else { return nil }
        return (parts, alphaToken)
    }

    /// A component normalized to 0...1: `n%` is a percentage, a bare number
    /// is on the given scale (255 for RGB channels, 100 for HSL
    /// saturation/lightness, 1 for alpha). Clamped.
    private static func unit(_ token: String, scale: Double) -> Double? {
        let value: Double
        if token.hasSuffix("%") {
            guard let percent = Double(token.dropLast()) else { return nil }
            value = percent / 100
        } else {
            guard let number = Double(token) else { return nil }
            value = number / scale
        }
        return min(max(value, 0), 1)
    }

    /// A hue in degrees, normalized to 0..<360. Bare numbers are degrees.
    private static func hue(_ token: String) -> Double? {
        let units: [(String, Double)] = [("deg", 1), ("grad", 0.9), ("rad", 180 / .pi), ("turn", 360)]
        var degrees: Double?
        for (suffix, factor) in units where token.hasSuffix(suffix) {
            degrees = Double(token.dropLast(suffix.count)).map { $0 * factor }
            break
        }
        guard let resolved = degrees ?? Double(token) else { return nil }
        let wrapped = resolved.truncatingRemainder(dividingBy: 360)
        return wrapped < 0 ? wrapped + 360 : wrapped
    }

    private static func fromHSL(_ hueDegrees: Double, _ saturation: Double, _ lightness: Double) -> RichTextColor {
        /// CSS Color 4 §7.1 reference algorithm.
        func channel(_ offset: Double) -> Double {
            let position = (offset + hueDegrees / 30).truncatingRemainder(dividingBy: 12)
            let amplitude = saturation * min(lightness, 1 - lightness)
            return lightness - amplitude * max(-1, min(position - 3, 9 - position, 1))
        }
        return RichTextColor(red: byte(channel(0)), green: byte(channel(8)), blue: byte(channel(4)))
    }

    private static func byte(_ unit: Double) -> UInt8 {
        UInt8((min(max(unit, 0), 1) * 255).rounded())
    }

    // MARK: - Named colors

    /// All 148 CSS named colors (CSS Color 4 §6.1), `transparent` excluded.
    static let named: [String: String] = [
        "aliceblue": "#f0f8ff", "antiquewhite": "#faebd7", "aqua": "#00ffff",
        "aquamarine": "#7fffd4", "azure": "#f0ffff", "beige": "#f5f5dc",
        "bisque": "#ffe4c4", "black": "#000000", "blanchedalmond": "#ffebcd",
        "blue": "#0000ff", "blueviolet": "#8a2be2", "brown": "#a52a2a",
        "burlywood": "#deb887", "cadetblue": "#5f9ea0", "chartreuse": "#7fff00",
        "chocolate": "#d2691e", "coral": "#ff7f50", "cornflowerblue": "#6495ed",
        "cornsilk": "#fff8dc", "crimson": "#dc143c", "cyan": "#00ffff",
        "darkblue": "#00008b", "darkcyan": "#008b8b", "darkgoldenrod": "#b8860b",
        "darkgray": "#a9a9a9", "darkgreen": "#006400", "darkgrey": "#a9a9a9",
        "darkkhaki": "#bdb76b", "darkmagenta": "#8b008b", "darkolivegreen": "#556b2f",
        "darkorange": "#ff8c00", "darkorchid": "#9932cc", "darkred": "#8b0000",
        "darksalmon": "#e9967a", "darkseagreen": "#8fbc8f", "darkslateblue": "#483d8b",
        "darkslategray": "#2f4f4f", "darkslategrey": "#2f4f4f", "darkturquoise": "#00ced1",
        "darkviolet": "#9400d3", "deeppink": "#ff1493", "deepskyblue": "#00bfff",
        "dimgray": "#696969", "dimgrey": "#696969", "dodgerblue": "#1e90ff",
        "firebrick": "#b22222", "floralwhite": "#fffaf0", "forestgreen": "#228b22",
        "fuchsia": "#ff00ff", "gainsboro": "#dcdcdc", "ghostwhite": "#f8f8ff",
        "gold": "#ffd700", "goldenrod": "#daa520", "gray": "#808080",
        "green": "#008000", "greenyellow": "#adff2f", "grey": "#808080",
        "honeydew": "#f0fff0", "hotpink": "#ff69b4", "indianred": "#cd5c5c",
        "indigo": "#4b0082", "ivory": "#fffff0", "khaki": "#f0e68c",
        "lavender": "#e6e6fa", "lavenderblush": "#fff0f5", "lawngreen": "#7cfc00",
        "lemonchiffon": "#fffacd", "lightblue": "#add8e6", "lightcoral": "#f08080",
        "lightcyan": "#e0ffff", "lightgoldenrodyellow": "#fafad2", "lightgray": "#d3d3d3",
        "lightgreen": "#90ee90", "lightgrey": "#d3d3d3", "lightpink": "#ffb6c1",
        "lightsalmon": "#ffa07a", "lightseagreen": "#20b2aa", "lightskyblue": "#87cefa",
        "lightslategray": "#778899", "lightslategrey": "#778899", "lightsteelblue": "#b0c4de",
        "lightyellow": "#ffffe0", "lime": "#00ff00", "limegreen": "#32cd32",
        "linen": "#faf0e6", "magenta": "#ff00ff", "maroon": "#800000",
        "mediumaquamarine": "#66cdaa", "mediumblue": "#0000cd", "mediumorchid": "#ba55d3",
        "mediumpurple": "#9370db", "mediumseagreen": "#3cb371", "mediumslateblue": "#7b68ee",
        "mediumspringgreen": "#00fa9a", "mediumturquoise": "#48d1cc", "mediumvioletred": "#c71585",
        "midnightblue": "#191970", "mintcream": "#f5fffa", "mistyrose": "#ffe4e1",
        "moccasin": "#ffe4b5", "navajowhite": "#ffdead", "navy": "#000080",
        "oldlace": "#fdf5e6", "olive": "#808000", "olivedrab": "#6b8e23",
        "orange": "#ffa500", "orangered": "#ff4500", "orchid": "#da70d6",
        "palegoldenrod": "#eee8aa", "palegreen": "#98fb98", "paleturquoise": "#afeeee",
        "palevioletred": "#db7093", "papayawhip": "#ffefd5", "peachpuff": "#ffdab9",
        "peru": "#cd853f", "pink": "#ffc0cb", "plum": "#dda0dd",
        "powderblue": "#b0e0e6", "purple": "#800080", "rebeccapurple": "#663399",
        "red": "#ff0000", "rosybrown": "#bc8f8f", "royalblue": "#4169e1",
        "saddlebrown": "#8b4513", "salmon": "#fa8072", "sandybrown": "#f4a460",
        "seagreen": "#2e8b57", "seashell": "#fff5ee", "sienna": "#a0522d",
        "silver": "#c0c0c0", "skyblue": "#87ceeb", "slateblue": "#6a5acd",
        "slategray": "#708090", "slategrey": "#708090", "snow": "#fffafa",
        "springgreen": "#00ff7f", "steelblue": "#4682b4", "tan": "#d2b48c",
        "teal": "#008080", "thistle": "#d8bfd8", "tomato": "#ff6347",
        "turquoise": "#40e0d0", "violet": "#ee82ee", "wheat": "#f5deb3",
        "white": "#ffffff", "whitesmoke": "#f5f5f5", "yellow": "#ffff00",
        "yellowgreen": "#9acd32",
    ]
}
