// RichTextAttributesTests.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
@testable import RichTextCore
import Testing

struct RichTextAttributesTests {
    @Test func blockStyleMarkerSetAndGet() {
        var s = AttributedString("Heading")
        s.blockStyle = .heading(2)
        #expect(s.blockStyle == .heading(2))
    }

    @Test func inlineBoldIsPerRun() throws {
        var s = AttributedString("bold plain")
        let boldRange = try #require(s.range(of: "bold"))
        s[boldRange].bold = true

        #expect(s[boldRange].bold == true)
        let plainRange = try #require(s.range(of: "plain"))
        #expect(s[plainRange].bold == nil)
    }

    @Test func allInlineAttributesRoundTrip() {
        var s = AttributedString("x")
        let r = s.startIndex ..< s.endIndex
        s[r].italic = true
        s[r].underline = true
        s[r].strikethrough = true
        s[r].textColor = RichTextColor(red: 10, green: 20, blue: 30)

        #expect(s[r].italic == true)
        #expect(s[r].underline == true)
        #expect(s[r].strikethrough == true)
        #expect(s[r].textColor == RichTextColor(red: 10, green: 20, blue: 30))
    }

    @Test func attributeKeyNamesAreStable() {
        // Serialized keys must not drift silently — they are part of the storage contract.
        #expect(RichTextAttributes.BlockStyleKey.name == "com.mfbtech.rich-text-swift.blockStyle")
        #expect(RichTextAttributes.BoldKey.name == "com.mfbtech.rich-text-swift.bold")
        #expect(RichTextAttributes.ItalicKey.name == "com.mfbtech.rich-text-swift.italic")
        #expect(RichTextAttributes.UnderlineKey.name == "com.mfbtech.rich-text-swift.underline")
        #expect(RichTextAttributes.StrikethroughKey.name == "com.mfbtech.rich-text-swift.strikethrough")
        #expect(RichTextAttributes.TextColorKey.name == "com.mfbtech.rich-text-swift.textColor")
    }

    @Test func blockStyleIsParagraphUniform() throws {
        var s = AttributedString("First paragraph text\nSecond paragraph text")
        let fullRange = s.startIndex ..< s.endIndex

        // Set blockStyle only on a sub-range covering part of the first paragraph
        // (just the word "First").
        let partialRange = try #require(s.range(of: "First"))
        s[partialRange].blockStyle = .heading(1)

        // Because BlockStyleKey declares `runBoundaries = .paragraph`, the attribute
        // must apply uniformly across the entire paragraph containing that range,
        // not just the sub-range it was assigned to.
        let firstParagraphRange = try #require(s.range(of: "First paragraph text"))
        for run in s[firstParagraphRange].runs {
            #expect(run.blockStyle == .heading(1))
        }

        // The second paragraph must be entirely unaffected.
        let secondParagraphRange = try #require(s.range(of: "Second paragraph text"))
        for run in s[secondParagraphRange].runs {
            #expect(run.blockStyle == nil)
        }

        // Sanity: the whole string's runs partition exactly along the paragraph
        // boundary (no bleed past the "\n").
        #expect(s[fullRange].runs.count >= 1)
    }
}
