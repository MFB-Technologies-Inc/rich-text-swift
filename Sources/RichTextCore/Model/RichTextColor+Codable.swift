// RichTextColor+Codable.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation

/// Hand-written so the saved format is a plain `"#rrggbb"` string, matching
/// the HTML encoder, rather than whatever the stored properties are named
/// (GitHub issue #82). `CodableFormatTests` pins this; change it only on
/// purpose.
extension RichTextColor {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let hex = try container.decode(String.self)
        guard let color = RichTextColor(hex: hex) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected a #rrggbb color, found \"\(hex)\"."
            )
        }
        self = color
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hexString)
    }
}
