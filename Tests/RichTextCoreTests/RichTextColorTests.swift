// RichTextColorTests.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

@testable import RichTextCore
import Testing

struct RichTextColorTests {
    @Test func hexStringIsLowercaseSixDigit() {
        #expect(RichTextColor(red: 255, green: 0, blue: 0).hexString == "#ff0000")
        #expect(RichTextColor(red: 0, green: 128, blue: 255).hexString == "#0080ff")
    }

    @Test func parsesSixDigitHexCaseInsensitively() {
        #expect(RichTextColor(hex: "#FF0000") == RichTextColor(red: 255, green: 0, blue: 0))
        #expect(RichTextColor(hex: "0080ff") == RichTextColor(red: 0, green: 128, blue: 255))
    }

    @Test func expandsThreeDigitShorthand() {
        #expect(RichTextColor(hex: "#f00") == RichTextColor(red: 255, green: 0, blue: 0))
        #expect(RichTextColor(hex: "#0af") == RichTextColor(red: 0, green: 170, blue: 255))
    }

    @Test func rejectsMalformedHex() {
        #expect(RichTextColor(hex: "") == nil)
        #expect(RichTextColor(hex: "#12") == nil)
        #expect(RichTextColor(hex: "#gg0000") == nil)
        #expect(RichTextColor(hex: "nonsense") == nil)
    }

    @Test func roundTripsThroughHex() {
        let c = RichTextColor(red: 18, green: 52, blue: 86)
        #expect(RichTextColor(hex: c.hexString) == c)
    }
}
