// HTMLColorTests.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

@testable import RichTextCore
import Testing

struct HTMLColorTests {
    @Test func parsesHex() {
        #expect(HTMLColor.parse("#ff0000") == RichTextColor(red: 255, green: 0, blue: 0))
        #expect(HTMLColor.parse("#F00") == RichTextColor(red: 255, green: 0, blue: 0))
    }

    @Test func parsesRGBFunction() {
        #expect(HTMLColor.parse("rgb(0, 128, 255)") == RichTextColor(red: 0, green: 128, blue: 255))
        #expect(HTMLColor.parse("rgb(300,-5,10)") == RichTextColor(red: 255, green: 0, blue: 10)) // clamped
    }

    @Test func parsesNamedColorsCaseInsensitively() {
        #expect(HTMLColor.parse("Red") == RichTextColor(red: 255, green: 0, blue: 0))
        #expect(HTMLColor.parse("BLUE") == RichTextColor(red: 0, green: 0, blue: 255))
        #expect(HTMLColor.parse("grey") == HTMLColor.parse("gray"))
    }

    @Test func rejectsUnknown() {
        #expect(HTMLColor.parse("notacolor") == nil)
        #expect(HTMLColor.parse("") == nil)
        #expect(HTMLColor.parse("rgb(1,2)") == nil)
    }

    @Test func extractsColorFromStyle() {
        #expect(HTMLColor.colorFromStyle("color: #ff0000") == RichTextColor(red: 255, green: 0, blue: 0))
        #expect(HTMLColor.colorFromStyle("font-weight:bold; color:rgb(0,0,0); margin:0")
            == RichTextColor(red: 0, green: 0, blue: 0))
        #expect(HTMLColor.colorFromStyle("font-weight:bold") == nil)
    }

    // MARK: - Import tolerance (text-color findings C3/C4)

    private static let red = RichTextColor(red: 255, green: 0, blue: 0)

    @Test func stripsImportant() {
        #expect(HTMLColor.parse("#FF0000 !important") == Self.red)
        #expect(HTMLColor.parse("rgb(255, 0, 0) !IMPORTANT") == Self.red)
    }

    @Test func parsesRGBAAndDropsOpaqueEnoughAlpha() {
        #expect(HTMLColor.parse("rgba(255, 0, 0, 1)") == Self.red)
        #expect(HTMLColor.parse("rgba(255, 0, 0, 0.5)") == Self.red)
        #expect(HTMLColor.parse("rgb(255, 0, 0, 0.8)") == Self.red)
        #expect(HTMLColor.parse("rgba(255, 0, 0, 80%)") == Self.red)
    }

    @Test func mostlyTransparentParsesToNoColor() {
        // `.black` is the model's "no color": a recognized request for no
        // visible color, which must clear an inherited one.
        #expect(HTMLColor.parse("rgba(255, 0, 0, 0.49)") == .black)
        #expect(HTMLColor.parse("rgba(255, 0, 0, 0)") == .black)
        #expect(HTMLColor.parse("rgb(255 0 0 / 20%)") == .black)
        #expect(HTMLColor.parse("transparent") == .black)
    }

    @Test func parsesSpaceSyntaxAndSlashAlpha() {
        #expect(HTMLColor.parse("rgb(255 0 0)") == Self.red)
        #expect(HTMLColor.parse("rgb(255 0 0 / 50%)") == Self.red)
        #expect(HTMLColor.parse("rgb(255 0 0 / 1)") == Self.red)
        #expect(HTMLColor.parse("rgb(255 0 0 0.5)") == Self.red)
    }

    @Test func parsesPercentageAndFractionalComponents() {
        #expect(HTMLColor.parse("rgb(100%, 0%, 0%)") == Self.red)
        #expect(HTMLColor.parse("rgb(50%, 0%, 100%)") == RichTextColor(red: 128, green: 0, blue: 255))
        #expect(HTMLColor.parse("rgb(254.6, 0, 0)") == Self.red)
    }

    @Test func parsesHSL() {
        #expect(HTMLColor.parse("hsl(0, 100%, 50%)") == Self.red)
        #expect(HTMLColor.parse("hsla(120, 100%, 25%, 1)") == RichTextColor(red: 0, green: 128, blue: 0))
        #expect(HTMLColor.parse("hsl(240deg 100% 50%)") == RichTextColor(red: 0, green: 0, blue: 255))
        #expect(HTMLColor.parse("hsl(0.5turn, 100%, 50%)") == RichTextColor(red: 0, green: 255, blue: 255))
        #expect(HTMLColor.parse("hsl(-120, 100%, 50%)") == RichTextColor(red: 0, green: 0, blue: 255))
        #expect(HTMLColor.parse("hsl(0, 0%, 100%)") == RichTextColor(red: 255, green: 255, blue: 255))
        #expect(HTMLColor.parse("hsl(0, 100%, 50%, 0.1)") == .black)
    }

    @Test func parsesExtendedNamedColors() {
        #expect(HTMLColor.parse("darkred") == RichTextColor(red: 0x8B, green: 0, blue: 0))
        #expect(HTMLColor.parse("RebeccaPurple") == RichTextColor(red: 0x66, green: 0x33, blue: 0x99))
        #expect(HTMLColor.parse("cornflowerblue") == RichTextColor(red: 0x64, green: 0x95, blue: 0xED))
        #expect(HTMLColor.named.count == 148)
        for (name, hex) in HTMLColor.named {
            #expect(RichTextColor(hex: hex) != nil, "bad hex for \(name)")
        }
    }

    @Test func unrecognizedValuesStillParseToNil() {
        for value in [
            "windowtext",
            "inherit",
            "currentcolor",
            "initial",
            "rgb(1,2)",
            "rgb(a,b,c)",
            "hsl(0, 100%)",
            "rgb(1 2 3 / 4 / 5)",
            "#12345",
        ] {
            #expect(HTMLColor.parse(value) == nil, "\(value)")
        }
    }

    @Test func lastColorDeclarationWins() {
        #expect(HTMLColor.colorFromStyle("color:red;color:blue") == RichTextColor(red: 0, green: 0, blue: 255))
        // An unparseable later declaration is dropped, as a browser would.
        #expect(HTMLColor.colorFromStyle("color:red;color:windowtext") == Self.red)
    }

    @Test func importantDeclarationBeatsLaterNormalOne() {
        #expect(HTMLColor.colorFromStyle("color:red !important;color:blue") == Self.red)
        #expect(HTMLColor.colorFromStyle("color:blue !important;color:red !important") == Self.red)
    }
}
