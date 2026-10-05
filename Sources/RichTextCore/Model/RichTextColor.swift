// RichTextColor.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation

/// A framework-neutral RGB color. Deliberately not `UIColor`/`Color` so the
/// core stays platform-agnostic. The serializer emits/accepts it as hex.
public struct RichTextColor: Codable, Hashable, Sendable {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Parses `#rgb` / `#rrggbb` (leading `#` optional, case-insensitive).
    /// Returns `nil` for anything else.
    public init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespaces).lowercased()
        if text.hasPrefix("#") {
            text.removeFirst()
        }
        let chars = Array(text)

        func nibble(_ char: Character) -> UInt8? {
            UInt8(String(char), radix: 16)
        }
        func byte(_ high: Character, _ low: Character) -> UInt8? {
            UInt8(String([high, low]), radix: 16)
        }

        switch chars.count {
        case 3:
            guard let red = nibble(chars[0]),
                  let green = nibble(chars[1]),
                  let blue = nibble(chars[2]) else { return nil }
            self.init(red: red << 4 | red, green: green << 4 | green, blue: blue << 4 | blue)
        case 6:
            guard let red = byte(chars[0], chars[1]),
                  let green = byte(chars[2], chars[3]),
                  let blue = byte(chars[4], chars[5]) else { return nil }
            self.init(red: red, green: green, blue: blue)
        default:
            return nil
        }
    }

    /// Lowercase `#rrggbb`.
    public var hexString: String {
        String(format: "#%02x%02x%02x", Int(red), Int(green), Int(blue))
    }

    /// Black is treated as the absence of a text color everywhere in the
    /// system (see `EngineCore+Inline.swift`, `HTMLDecoder`, `HTMLEncoder`):
    /// an explicit `#000000` would stay black in dark mode and become
    /// invisible against the background, where omitting the attribute lets
    /// the theme's default color adapt. It is also the value the system
    /// `ColorPicker` cannot avoid producing when there is "no color" to show,
    /// so picking black doubles as the remove gesture.
    public static let black = RichTextColor(red: 0, green: 0, blue: 0)
}
