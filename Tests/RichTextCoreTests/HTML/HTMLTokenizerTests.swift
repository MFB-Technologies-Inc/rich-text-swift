// HTMLTokenizerTests.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

@testable import RichTextCore
import Testing

struct HTMLTokenizerTests {
    @Test func tokenizesTextOnly() {
        #expect(HTMLTokenizer.tokenize("hello") == [.text("hello")])
    }

    @Test func tokenizesSimpleTags() {
        #expect(HTMLTokenizer.tokenize("<b>hi</b>") == [
            .startTag(name: "b", attributes: [:], selfClosing: false),
            .text("hi"),
            .endTag(name: "b"),
        ])
    }

    @Test func lowercasesTagNames() {
        #expect(HTMLTokenizer.tokenize("<P>x</P>") == [
            .startTag(name: "p", attributes: [:], selfClosing: false),
            .text("x"),
            .endTag(name: "p"),
        ])
    }

    @Test func parsesAttributesAllQuotingStyles() {
        #expect(HTMLTokenizer.tokenize("<span style=\"color:#f00\" data-x='y' flag>t</span>") == [
            .startTag(
                name: "span",
                attributes: ["style": "color:#f00", "data-x": "y", "flag": ""],
                selfClosing: false
            ),
            .text("t"),
            .endTag(name: "span"),
        ])
    }

    @Test func treatsBrAsSelfClosingVoid() {
        #expect(HTMLTokenizer.tokenize("a<br>b") == [
            .text("a"),
            .startTag(name: "br", attributes: [:], selfClosing: true),
            .text("b"),
        ])
        #expect(HTMLTokenizer.tokenize("a<br/>b") == HTMLTokenizer.tokenize("a<br>b"))
    }

    @Test func decodesEntitiesInText() {
        #expect(HTMLTokenizer.tokenize("a &amp; b") == [.text("a & b")])
    }

    @Test func skipsCommentsAndDoctype() {
        #expect(HTMLTokenizer.tokenize("<!doctype html><!-- c --><p>x</p>") == [
            .startTag(name: "p", attributes: [:], selfClosing: false),
            .text("x"),
            .endTag(name: "p"),
        ])
    }

    @Test func toleratesStrayLessThan() {
        #expect(HTMLTokenizer.tokenize("a < b") == [.text("a < b")])
    }

    @Test func toleratesUnterminatedTag() {
        // Unterminated tag at EOF is dropped; preceding text preserved.
        #expect(HTMLTokenizer.tokenize("hello <b") == [.text("hello ")])
    }

    @Test func toleratesUnterminatedEndTag() {
        #expect(HTMLTokenizer.tokenize("hello </b") == [.text("hello ")])
    }

    @Test func keepsTextOnBothSidesOfSkippedMarkup() {
        #expect(HTMLTokenizer.tokenize("a<!-- c -->b<!doctype html>c < d") == [
            .text("a"),
            .text("b"),
            .text("c < d"),
        ])
    }

    /// The tokenizer must treat every tag `HTMLTagClasses.void` knows about as
    /// self-closing, not just the original hand-picked six (`br`, `hr`, `img`,
    /// `input`, `meta`, `link`). Before `HTMLTagClasses.void` became the single
    /// source of truth, `<wbr>` and `<source>` tokenized as ordinary start
    /// tags — which, once the decoder opens a block/skip-content region for
    /// unrecognized tags, would leave that region open for the rest of the
    /// document.
    @Test func treatsAllVoidElementsFromHTMLTagClassesAsSelfClosing() {
        for tag in HTMLTagClasses.void {
            #expect(
                HTMLTokenizer.tokenize("<\(tag)>") == [.startTag(name: tag, attributes: [:], selfClosing: true)],
                "<\(tag)> must tokenize as self-closing"
            )
        }
    }

    @Test func wbrIsSelfClosing() {
        #expect(HTMLTokenizer.tokenize("<wbr>") == [.startTag(name: "wbr", attributes: [:], selfClosing: true)])
    }

    @Test func sourceIsSelfClosing() {
        #expect(HTMLTokenizer.tokenize("<source>") == [.startTag(name: "source", attributes: [:], selfClosing: true)])
    }

    // MARK: - Line endings

    // The tokenizer turns CR LF and bare CR into LF, as HTML input
    // preprocessing does. Entities decode afterward, so `&#13;` stays a CR.

    @Test func normalizesLineEndingsInText() {
        #expect(HTMLTokenizer.tokenize("a\r\nb\rc") == [.text("a\nb\nc")])
    }

    @Test func normalizesLineEndingsInAttributeValues() {
        #expect(HTMLTokenizer.tokenize("<p title=\"a\r\nb\rc\">") == [
            .startTag(name: "p", attributes: ["title": "a\nb\nc"], selfClosing: false),
        ])
    }

    @Test func normalizesLineEndingsOnBothSidesOfATag() {
        #expect(HTMLTokenizer.tokenize("a\r<b>\r\nc") == [
            .text("a\n"),
            .startTag(name: "b", attributes: [:], selfClosing: false),
            .text("\nc"),
        ])
    }

    @Test func treatsCRLFAsWhitespaceInsideTags() {
        #expect(HTMLTokenizer.tokenize("<p\r\nclass=x\r\n>") == [
            .startTag(name: "p", attributes: ["class": "x"], selfClosing: false),
        ])
    }

    @Test func leavesEntityEncodedCRAlone() {
        #expect(HTMLTokenizer.tokenize("a&#13;b") == [.text("a\rb")])
    }

    // MARK: - Non-ASCII input

    // The tokenizer scans UTF-8 bytes. It keeps one rule from the `Character`-
    // based tokenizer it replaced: an ASCII byte followed by a combining mark is
    // one grapheme cluster, so it is never a delimiter or a tag-name letter.
    // It deliberately drops the other half of that rule: a preceding Prepend
    // scalar (U+0600, U+0D4E, ...) no longer absorbs the delimiter after it,
    // which matches how browsers tokenize by code point.

    @Test func preservesMultiByteTextAndAttributeValues() {
        #expect(HTMLTokenizer.tokenize("<p title=\"héllo 😀\">naïve</p>") == [
            .startTag(name: "p", attributes: ["title": "héllo 😀"], selfClosing: false),
            .text("naïve"),
            .endTag(name: "p"),
        ])
    }

    @Test func decodesEntitiesBetweenMultiByteText() {
        #expect(HTMLTokenizer.tokenize("café &amp; 😀") == [.text("café & 😀")])
    }

    @Test func combiningMarkOnTagNameStartIsLiteralText() {
        #expect(HTMLTokenizer.tokenize("<a\u{0301}>x") == [.text("<a\u{0301}>x")])
    }

    @Test func combiningMarkEndsTagName() {
        #expect(HTMLTokenizer.tokenize("<span\u{0303}>t") == [
            .startTag(name: "spa", attributes: ["n\u{0303}": ""], selfClosing: false),
            .text("t"),
        ])
    }

    @Test func combiningMarkOnEndTagNameDoesNotCloseThatTag() {
        #expect(HTMLTokenizer.tokenize("<a>x</a\u{0301}>y") == [
            .startTag(name: "a", attributes: [:], selfClosing: false),
            .text("x"),
            .endTag(name: ""),
            .text("y"),
        ])
    }

    @Test func combiningMarkOnGreaterThanDoesNotCloseTag() {
        #expect(HTMLTokenizer.tokenize("<a title=x>\u{0338}y>z") == [
            .startTag(name: "a", attributes: ["title": "x>\u{0338}y"], selfClosing: false),
            .text("z"),
        ])
    }

    @Test func combiningMarkOnClosingQuoteDoesNotEndValue() {
        #expect(HTMLTokenizer.tokenize("<a title=\"x\"\u{0301} y\">z") == [
            .startTag(name: "a", attributes: ["title": "x\"\u{0301} y"], selfClosing: false),
            .text("z"),
        ])
    }

    @Test func combiningMarkOnCommentCloseDoesNotEndComment() {
        #expect(HTMLTokenizer.tokenize("<!-- a -->\u{0301} b -->c") == [.text("c")])
    }

    @Test func prependScalarBeforeLessThanDoesNotHideTag() {
        #expect(HTMLTokenizer.tokenize("\u{0600}<b>x</b>") == [
            .text("\u{0600}"),
            .startTag(name: "b", attributes: [:], selfClosing: false),
            .text("x"),
            .endTag(name: "b"),
        ])
    }

    @Test func prependScalarBeforeAmpersandDoesNotHideEntity() {
        #expect(HTMLTokenizer.tokenize("\u{0600}&amp;x") == [.text("\u{0600}&x")])
        #expect(HTMLTokenizer.tokenize("<p title=\"\u{0600}&amp;x\">") == [
            .startTag(name: "p", attributes: ["title": "\u{0600}&x"], selfClosing: false),
        ])
    }

    @Test func prependScalarBeforeClosingQuoteEndsValue() {
        #expect(HTMLTokenizer.tokenize("<p title=\"x\u{0600}\">y</p>") == [
            .startTag(name: "p", attributes: ["title": "x\u{0600}"], selfClosing: false),
            .text("y"),
            .endTag(name: "p"),
        ])
    }
}
