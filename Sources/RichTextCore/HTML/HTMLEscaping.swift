// HTMLEscaping.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation

enum HTMLEscaping {
    /// Both escapers switch on unicode scalars, not `Character`s: a special
    /// followed by a combining mark (e.g. "<\u{301}") is one grapheme cluster
    /// that is `!=` "<", so a per-Character switch would let the raw special
    /// through into the markup.
    static func escapeText(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.utf8.count)
        for scalar in text.unicodeScalars {
            switch scalar {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out
    }

    static func escapeAttribute(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.utf8.count)
        for scalar in text.unicodeScalars {
            switch scalar {
            case "&": out += "&amp;"
            case "\"": out += "&quot;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out
    }

    static func decodeEntities(_ text: String) -> String {
        let scalars = text.unicodeScalars
        guard scalars.contains("&") else { return text }
        var out = ""
        out.reserveCapacity(text.utf8.count)
        var index = scalars.startIndex
        while index < scalars.endIndex {
            if scalars[index] == "&" {
                // Only a semicolon within 12 scalars of '&' can end a
                // supported entity. Stop there so stray '&' stays cheap.
                var semi = scalars.index(after: index)
                var distance = 1
                while semi < scalars.endIndex, distance <= 12, scalars[semi] != ";" {
                    semi = scalars.index(after: semi)
                    distance += 1
                }
                if semi < scalars.endIndex, distance <= 12, scalars[semi] == ";" {
                    let body = String(scalars[scalars.index(after: index) ..< semi])
                    if let decoded = decodeSingle(body) {
                        out += decoded
                        index = scalars.index(after: semi)
                        continue
                    }
                }
            }
            out.unicodeScalars.append(scalars[index])
            index = scalars.index(after: index)
        }
        return out
    }

    private static func decodeSingle(_ entity: String) -> String? {
        if entity.hasPrefix("#") {
            let num = entity.dropFirst()
            let value: UInt32? = if let first = num.first, first == "x" || first == "X" {
                UInt32(num.dropFirst(), radix: 16)
            } else {
                UInt32(num, radix: 10)
            }
            if let value, let scalar = Unicode.Scalar(value) {
                return String(scalar)
            }
            return nil
        }
        return named[entity]
    }

    static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
        "nbsp": "\u{00A0}", "copy": "\u{00A9}", "reg": "\u{00AE}",
        "hellip": "\u{2026}", "mdash": "\u{2014}", "ndash": "\u{2013}",
        "lsquo": "\u{2018}", "rsquo": "\u{2019}", "ldquo": "\u{201C}", "rdquo": "\u{201D}",
    ]
}
