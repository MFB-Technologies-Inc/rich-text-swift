// HTMLEncoderTests.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
@testable import RichTextCore
import Testing

struct HTMLEncoderTests {
    @Test func encodesParagraph() {
        #expect(RichTextHTML.encode(Sem.block("Hello")) == "<p>Hello</p>")
    }

    @Test func encodesHeadings() {
        #expect(RichTextHTML.encode(Sem.block("Title", .heading(1))) == "<h1>Title</h1>")
        #expect(RichTextHTML.encode(Sem.block("Sub", .heading(3))) == "<h3>Sub</h3>")
    }

    @Test func clampsHeadingLevel() {
        #expect(RichTextHTML.encode(Sem.block("X", .heading(9))) == "<h3>X</h3>")
    }

    @Test func escapesText() {
        #expect(RichTextHTML.encode(Sem.block("a & b < c")) == "<p>a &amp; b &lt; c</p>")
    }

    /// A special followed by a combining mark is a single grapheme cluster
    /// that is not equal to `"<"`, so escaping must look at scalars.
    @Test func escapesSpecialsFollowedByACombiningMark() {
        #expect(RichTextHTML.encode(Sem.block("<\u{301}script>")) == "<p>&lt;\u{301}script&gt;</p>")
        #expect(RichTextHTML.encode(Sem.block("a &\u{301} b >\u{301}")) == "<p>a &amp;\u{301} b &gt;\u{301}</p>")
    }

    @Test func encodesMultipleBlocks() {
        let doc = Sem.doc(Sem.block("One", .heading(1)), Sem.block("Two"))
        #expect(RichTextHTML.encode(doc) == "<h1>One</h1>\n<p>Two</p>")
    }

    @Test func encodesBoldItalicInCanonicalNesting() {
        var a = AttributedString("hi")
        a.blockStyle = .paragraph
        a.bold = true
        a.italic = true
        #expect(RichTextHTML.encode(a) == "<p><b><i>hi</i></b></p>")
    }

    @Test func encodesColorSpanOutermost() {
        var a = AttributedString("hi")
        a.blockStyle = .paragraph
        a.bold = true
        a.textColor = RichTextColor(red: 255, green: 0, blue: 0)
        #expect(RichTextHTML.encode(a) == "<p><span style=\"color:#ff0000\"><b>hi</b></span></p>")
    }

    @Test func encodesPartialInlineRuns() throws {
        var a = AttributedString("ab")
        a.blockStyle = .paragraph
        let boldRange = try #require(a.range(of: "a"))
        a[boldRange].bold = true
        #expect(RichTextHTML.encode(a) == "<p><b>a</b>b</p>")
    }

    @Test func encodesSoftBreakAsBr() {
        #expect(RichTextHTML.encode(Sem.block("a\u{2028}b")) == "<p>a<br>b</p>")
    }

    @Test func encodesUnorderedList() {
        let doc = Sem.doc(
            Sem.block("one", .listItem(.unordered, depth: 0)),
            Sem.block("two", .listItem(.unordered, depth: 0))
        )
        #expect(RichTextHTML.encode(doc) == "<ul><li>one</li><li>two</li></ul>")
    }

    @Test func encodesOrderedList() {
        let doc = Sem.doc(
            Sem.block("one", .listItem(.ordered, depth: 0)),
            Sem.block("two", .listItem(.ordered, depth: 0))
        )
        #expect(RichTextHTML.encode(doc) == "<ol><li>one</li><li>two</li></ol>")
    }

    @Test func encodesNestedList() {
        let doc = Sem.doc(
            Sem.block("a", .listItem(.unordered, depth: 0)),
            Sem.block("b", .listItem(.unordered, depth: 1)),
            Sem.block("c", .listItem(.unordered, depth: 0))
        )
        // F6: a nested list belongs *inside* the preceding <li>, not as its
        // sibling. `<ul><li>a</li><ul><li>b</li></ul><li>c</li></ul>` (the
        // old expectation here) is invalid HTML — a `<ul>` as a direct child
        // of `<ul>`.
        #expect(RichTextHTML.encode(doc)
            == "<ul><li>a<ul><li>b</li></ul></li><li>c</li></ul>")
    }

    @Test func listThenParagraphClosesList() {
        let doc = Sem.doc(
            Sem.block("item", .listItem(.unordered, depth: 0)),
            Sem.block("after")
        )
        #expect(RichTextHTML.encode(doc) == "<ul><li>item</li></ul>\n<p>after</p>")
    }

    @Test func encodesEmptyStringAsEmptyParagraph() {
        // A single empty block.
        #expect(RichTextHTML.encode(Sem.block("")) == "<p></p>")
    }

    // MARK: - Black is the absence of a text color

    @Test func encodingBlackEmitsNoColorSpan() {
        // Not merely defensive: `RichTextColor` and the model's attribute
        // keys are public, so a caller can build a document carrying an
        // explicit black `textColor` directly and hand it to `encode(_:)`,
        // bypassing the command layer and decoder's own normalization
        // entirely. Such a document is not in canonical form (see
        // `RichTextHTML.encode`'s doc comment), and this is the check that
        // actually guarantees black never leaks into HTML output.
        var a = AttributedString("hi")
        a.blockStyle = .paragraph
        a.textColor = RichTextColor(red: 0, green: 0, blue: 0)
        #expect(RichTextHTML.encode(a) == "<p>hi</p>")
    }

    @Test func encodingBlackAlongsideOtherFormattingStillOmitsTheSpan() {
        var a = AttributedString("hi")
        a.blockStyle = .paragraph
        a.bold = true
        a.textColor = RichTextColor(red: 0, green: 0, blue: 0)
        #expect(RichTextHTML.encode(a) == "<p><b>hi</b></p>")
    }
}
