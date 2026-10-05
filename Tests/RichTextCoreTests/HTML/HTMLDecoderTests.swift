// HTMLDecoderTests.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
@testable import RichTextCore
import Testing

struct HTMLDecoderTests {
    // Helper: assert decoded model equals an expected semantic doc.
    private func decode(_ html: String) -> AttributedString {
        RichTextHTML.decode(html)
    }

    @Test func decodesParagraph() {
        #expect(decode("<p>Hello</p>") == Sem.block("Hello"))
    }

    @Test func decodesHeading() {
        #expect(decode("<h2>Title</h2>") == Sem.block("Title", .heading(2)))
    }

    @Test func decodesBoldAndNormalizesStrong() {
        var expected = Sem.block("hi")
        expected.bold = true
        #expect(decode("<p><b>hi</b></p>") == expected)
        #expect(decode("<p><strong>hi</strong></p>") == expected)
    }

    @Test func normalizesEmToItalicAndStrikeVariants() {
        var em = Sem.block("x"); em.italic = true
        #expect(decode("<p><em>x</em></p>") == em)
        var st = Sem.block("y"); st.strikethrough = true
        #expect(decode("<p><strike>y</strike></p>") == st)
        #expect(decode("<p><del>y</del></p>") == st)
    }

    @Test func decodesColorSpanToHex() {
        var expected = Sem.block("c")
        expected.textColor = RichTextColor(red: 255, green: 0, blue: 0)
        #expect(decode("<p><span style=\"color: red\">c</span></p>") == expected)
        #expect(decode("<p><span style=\"color:#ff0000\">c</span></p>") == expected)
    }

    // MARK: - Black is the absence of a text color

    ///
    /// Black is never a meaningful "no color" in the theme: an explicit
    /// `#000000` would stay black in dark mode and become invisible, where
    /// omitting the attribute lets the theme's default adapt. So every spelling
    /// of black decodes to *no* color attribute at all, not to an RGB(0,0,0)
    /// run. (`HTMLColor.parse`/`colorFromStyle` themselves still parse black to
    /// RGB(0,0,0) correctly — see HTMLColorTests — this normalization is the
    /// decoder's job, one layer up.)
    @Test func decodingBlackColorSpanProducesNoColorAttribute() {
        let expected = Sem.block("c")
        #expect(decode("<p><span style=\"color:#000000\">c</span></p>") == expected)
        #expect(decode("<p><span style=\"color:#000\">c</span></p>") == expected)
        #expect(decode("<p><span style=\"color:black\">c</span></p>") == expected)
        #expect(decode("<p><span style=\"color:rgb(0,0,0)\">c</span></p>") == expected)
    }

    @Test func decodingBlackAlongsideOtherFormattingStillDropsOnlyTheColor() {
        var expected = Sem.block("c")
        expected.bold = true
        #expect(decode("<p><span style=\"color:#000000\"><b>c</b></span></p>") == expected)
    }

    /// A black span nested in a colored one must *clear* the inherited color:
    /// black was ZSS's only "remove color" gesture, so this is how existing
    /// notes express un-coloring one word of a colored sentence.
    @Test(arguments: ["#000000", "rgb(0, 0, 0)", "black"])
    func nestedBlackSpanClearsInheritedColor(_ black: String) {
        let red = RichTextColor(red: 255, green: 0, blue: 0)
        var a = AttributedString("a"); a.textColor = red
        let b = AttributedString("b")
        var c = AttributedString("c"); c.textColor = red
        var expected = a + b + c
        expected.blockStyle = .paragraph
        let html = "<p><span style=\"color:#ff0000\">a<span style=\"color:\(black)\">b</span>c</span></p>"
        #expect(decode(html) == expected)
    }

    @Test func nestedTransparentSpanClearsInheritedColor() {
        let red = RichTextColor(red: 255, green: 0, blue: 0)
        var a = AttributedString("a"); a.textColor = red
        var expected = a + AttributedString("b")
        expected.blockStyle = .paragraph
        #expect(decode("<p><span style=\"color:red\">a<span style=\"color:rgba(0,0,0,0)\">b</span></span></p>") ==
            expected)
    }

    @Test func nestedUnparseableColorInherits() {
        var expected = Sem.block("ab")
        expected.textColor = RichTextColor(red: 255, green: 0, blue: 0)
        #expect(decode("<p><span style=\"color:red\">a<span style=\"color:windowtext\">b</span></span></p>") ==
            expected)
        #expect(decode("<p><span style=\"color:red\">a<span style=\"font-weight:normal\">b</span></span></p>") ==
            expected)
    }

    @Test func decodesFontColor() {
        var expected = Sem.block("c")
        expected.textColor = RichTextColor(red: 255, green: 0, blue: 0)
        #expect(decode("<p><font color=\"#ff0000\">c</font></p>") == expected)
        #expect(decode("<p><font color=\"red\">c</font></p>") == expected)
        #expect(decode("<p><FONT COLOR=\"Red\" face=\"Arial\">c</FONT></p>") == expected)
        // Inline style outranks the presentational attribute.
        #expect(decode("<p><font color=\"blue\" style=\"color:red\">c</font></p>") == expected)
    }

    @Test func fontColorBlackClearsInheritedColorAndBareFontInherits() {
        let red = RichTextColor(red: 255, green: 0, blue: 0)
        var a = AttributedString("a"); a.textColor = red
        var c = AttributedString("c"); c.textColor = red
        var expected = a + AttributedString("b") + c
        expected.blockStyle = .paragraph
        #expect(decode("<p><font color=\"red\">a<font color=\"#000000\">b</font>c</font></p>") == expected)

        var inherited = Sem.block("ab")
        inherited.textColor = red
        #expect(decode("<p><span style=\"color:red\">a<font face=\"Arial\">b</font></span></p>") == inherited)
    }

    @Test func spanIgnoresAColorAttribute() {
        // `color` is only a presentational attribute on `<font>`.
        #expect(decode("<p><span color=\"red\">c</span></p>") == Sem.block("c"))
    }

    @Test func decodingANearBlackColorIsNotNormalizedAway() {
        // Guard against over-normalizing: only exact black is special-cased.
        var expected = Sem.block("c")
        expected.textColor = RichTextColor(red: 0, green: 0, blue: 1)
        #expect(decode("<p><span style=\"color:#000001\">c</span></p>") == expected)
    }

    @Test func decodesBrAsSoftBreak() {
        #expect(decode("<p>a<br>b</p>") == Sem.block("a\u{2028}b"))
    }

    @Test func unwrapsUnmappedInlineTags() {
        // `<div>` is deliberately not used here: as of the block-level-tag
        // fix, an unrecognized tag defaults to
        // block-level, not inline-unwrapped. `<cite>` is a known-inline tag
        // with no dedicated switch case, so it still exercises the
        // default-branch unwrap path this test targets.
        #expect(decode("<p><font size=\"3\">keep <cite>text</cite></font></p>")
            == Sem.block("keep text"))
    }

    @Test func decodesUnorderedListWithDepth() {
        let expected = Sem.doc(
            Sem.block("a", .listItem(.unordered, depth: 0)),
            Sem.block("b", .listItem(.unordered, depth: 0))
        )
        #expect(decode("<ul><li>a</li><li>b</li></ul>") == expected)
    }

    @Test func decodesNestedList() {
        let expected = Sem.doc(
            Sem.block("a", .listItem(.unordered, depth: 0)),
            Sem.block("b", .listItem(.unordered, depth: 1))
        )
        #expect(decode("<ul><li>a</li><ul><li>b</li></ul></ul>") == expected)
    }

    @Test func collapsesWhitespaceAndTrimsBlocks() {
        #expect(decode("<p>  a    b  </p>") == Sem.block("a b"))
        #expect(decode("<p>x</p>\n  \n<p>y</p>") == Sem.doc(Sem.block("x"), Sem.block("y")))
    }

    @Test func wrapsLooseTextInImplicitParagraph() {
        #expect(decode("loose <b>text</b>") == {
            let a = AttributedString("loose ")
            var b = AttributedString("text"); b.bold = true
            var r = a; r += b; r.blockStyle = .paragraph
            return r
        }())
    }

    @Test func toleratesMismatchedTags() {
        // Stray close tag ignored; no crash; text preserved.
        var expected = Sem.block("hi"); expected.bold = true
        #expect(decode("<p><b>hi</u></b></p>") == expected)
    }

    @Test func preservesEmptyParagraph() {
        #expect(decode("<p>a</p><p></p><p>b</p>")
            == Sem.doc(Sem.block("a"), Sem.block(""), Sem.block("b")))
    }

    // MARK: - Non-ASCII run boundaries

    // The decoder builds runs by unicode scalar, not by `Character`, so an
    // inline attribute can end in the middle of a grapheme cluster, exactly
    // where the markup ends it. The combining marks are entity-encoded: a
    // literal one right after `</b>` would join the `>` and swallow the rest
    // of the input (see `HTMLTokenizerTests`).

    @Test func attributeEndsBeforeCombiningMarkThatStartsNextRun() {
        var a = AttributedString("a"); a.bold = true
        var expected = a + AttributedString("\u{0301}c")
        expected.blockStyle = .paragraph
        #expect(decode("<b>a</b>&#x301;c") == expected)
    }

    @Test func combiningMarkKeepsTheSpaceBeforeItFromCollapsing() {
        var a = AttributedString("a "); a.bold = true
        var expected = a + AttributedString("\u{0301}c")
        expected.blockStyle = .paragraph
        #expect(decode("<b>a </b>&#x301;c") == expected)
    }

    /// A Prepend scalar joins the space after it into one non-whitespace
    /// grapheme cluster, so neither collapsing nor the trailing trim removes it.
    @Test func spaceJoinedToPrependScalarIsNotTrimmed() {
        #expect(decode("<p>\u{0600} </p>") == Sem.block("\u{0600} "))
    }

    @Test func collapsedSpaceKeepsTheFirstRunsAttributes() {
        var x = AttributedString("x "); x.bold = true
        var y = AttributedString("y"); y.italic = true
        var expected = x + y
        expected.blockStyle = .paragraph
        #expect(decode("<b>x </b> <i>y</i>") == expected)
    }

    @Test func adjacentRunsWithSameAttributesJoinOneGraphemeCluster() {
        var expected = Sem.block("\u{1F1FA}\u{1F1F8}")
        expected.bold = true
        #expect(decode("<b>\u{1F1FA}</b><b>\u{1F1F8}</b>") == expected)
    }
}
