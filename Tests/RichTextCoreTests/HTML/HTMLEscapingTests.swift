// HTMLEscapingTests.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

@testable import RichTextCore
import Testing

struct HTMLEscapingTests {
    @Test func escapesTextSpecials() {
        #expect(HTMLEscaping.escapeText("a & b < c > d") == "a &amp; b &lt; c &gt; d")
        #expect(HTMLEscaping.escapeText("plain") == "plain")
        // Quotes are NOT escaped in text nodes.
        #expect(HTMLEscaping.escapeText("say \"hi\"") == "say \"hi\"")
    }

    @Test func escapesAttributeSpecials() {
        #expect(HTMLEscaping.escapeAttribute("a\"b&c") == "a&quot;b&amp;c")
    }

    @Test func decodesNamedEntities() {
        #expect(HTMLEscaping.decodeEntities("a &amp; b &lt; c &gt; &quot;q&quot; &nbsp;x")
            == "a & b < c > \"q\" \u{00A0}x")
    }

    @Test func decodesNumericEntities() {
        #expect(HTMLEscaping.decodeEntities("&#65;&#x42;&#x1F600;") == "AB\u{1F600}")
    }

    @Test func decodesEntityAfterPrependScalar() {
        #expect(HTMLEscaping.decodeEntities("\u{0600}&amp;x") == "\u{0600}&x")
    }

    @Test func leavesUnknownOrMalformedEntitiesLiteral() {
        #expect(HTMLEscaping.decodeEntities("100% & up") == "100% & up")
        #expect(HTMLEscaping.decodeEntities("&notanentity;") == "&notanentity;")
        #expect(HTMLEscaping.decodeEntities("bare & amp") == "bare & amp")
        #expect(HTMLEscaping.decodeEntities("&123456789012; &amp;") == "&123456789012; &")
    }

    @Test func escapesSpecialsFollowedByACombiningMark() {
        #expect(HTMLEscaping.escapeText("<\u{301}a>\u{301}&\u{301}") == "&lt;\u{301}a&gt;\u{301}&amp;\u{301}")
        #expect(HTMLEscaping.escapeAttribute("\"\u{301}<\u{301}") == "&quot;\u{301}&lt;\u{301}")
    }

    @Test func escapeThenDecodeRoundTrips() {
        let s = "a & b < c > d"
        #expect(HTMLEscaping.decodeEntities(HTMLEscaping.escapeText(s)) == s)
    }
}
