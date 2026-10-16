// MarkdownEncoderTests.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
@testable import RichTextCore
import Testing

/// Pins the exact canonical output, so it only ever changes on purpose.
struct MarkdownEncoderTests {
    private let ul0 = BlockStyle.listItem(.unordered, depth: 0)
    private let ul1 = BlockStyle.listItem(.unordered, depth: 1)
    private let ol0 = BlockStyle.listItem(.ordered, depth: 0)

    private func encode(_ document: AttributedString) -> String {
        RichTextMarkdown.encode(document)
    }

    @Test func blocks() {
        #expect(encode(Sem.block("Hello")) == "Hello")
        #expect(encode(Sem.block("T", .heading(1))) == "# T")
        #expect(encode(Sem.block("T", .heading(3))) == "### T")
        #expect(encode(Sem.block("T", .heading(5))) == "### T")
        #expect(encode(Sem.block("q", .blockquote)) == "> q")
        #expect(encode(Sem.doc(Sem.block("a"), Sem.block("b"))) == "a\n\nb")
        #expect(encode(Sem.doc(Sem.block("a", .blockquote), Sem.block("b", .blockquote))) == "> a\n\n> b")
    }

    @Test func emptyBlocksAreSkipped() {
        #expect(encode(Sem.doc(Sem.block("a"), Sem.block(""), Sem.block("b"))) == "a\n\nb")
        #expect(encode(AttributedString()) == "")
    }

    @Test func lists() {
        #expect(encode(Sem.doc(Sem.block("a", ul0), Sem.block("b", ul1), Sem.block("c", ul0))) == "- a\n  - b\n- c")
        #expect(encode(Sem.doc(Sem.block("a", ol0), Sem.block("b", ol0))) == "1. a\n2. b")
        #expect(encode(Sem.doc(Sem.block("a", ol0), Sem.block("b", ul1), Sem.block("c", ol0))) == "1. a\n   - b\n2. c")
        #expect(encode(Sem.doc(Sem.block("a", ul0), Sem.block("b", ol0))) == "- a\n1. b")
        #expect(encode(Sem.doc(Sem.block("p"), Sem.block("a", ul0), Sem.block("q"))) == "p\n\n- a\n\nq")
    }

    @Test func numberingRestartsAfterAnotherBlock() {
        #expect(encode(Sem.doc(Sem.block("a", ol0), Sem.block("p"), Sem.block("b", ol0))) == "1. a\n\np\n\n1. b")
    }

    @Test func childIndentFollowsATwoDigitNumber() {
        let items = (1 ... 10).map { Sem.block("i\($0)", ol0) } + [Sem.block("k", ul1)]
        let document = items.dropFirst().reduce(items[0]) { $0 + AttributedString("\n") + $1 }
        #expect(encode(document).hasSuffix("9. i9\n10. i10\n    - k"))
    }

    @Test func skippedDepthsShareTheItemsLine() {
        let deep = BlockStyle.listItem(.unordered, depth: 2)
        #expect(encode(Sem.doc(Sem.block("a", ul0), Sem.block("c", deep))) == "- a\n  - - c")
        #expect(encode(Sem.block("c", deep)) == "- - - c")
    }

    @Test func inlineMarks() {
        #expect(encode(MD.block(
            .paragraph,
            MD.run("a", .bold), MD.run(" "), MD.run("b", .italic), MD.run(" "), MD.run("c", .strikethrough)
        )) == "**a** *b* ~~c~~")
    }

    @Test func theSpanThatEndsLaterOpensFirst() {
        #expect(encode(MD.block(.paragraph, MD.run("a", .bold, .italic), MD.run("b", .italic))) == "***a**b*")
        #expect(encode(MD.block(.paragraph, MD.run("a", .bold, .italic), MD.run("b", .bold))) == "***a*b**")
    }

    @Test func separatorKeepsCrossingSpansApart() {
        #expect(encode(MD.block(
            .paragraph, MD.run("ab", .bold), MD.run("c", .bold, .italic), MD.run("d", .italic)
        )) == "**ab<!-- -->*c***<!-- -->*d*")
    }

    @Test func separatorKeepsMarksNextToPunctuationFlanking() {
        #expect(encode(MD.block(.paragraph, MD.run("a"), MD.run("\"b\"", .bold), MD.run("c")))
            == "a<!-- -->**\"b\"**<!-- -->c")
    }

    /// Foundation's parser reads a non-ASCII symbol as neither punctuation
    /// nor whitespace, while newer CommonMark reads it as punctuation, so a
    /// mark next to one gets the separator either reading needs.
    @Test(arguments: ["😀", "→", "€", "©"])
    func separatorKeepsMarksNextToSymbolsFlanking(_ symbol: String) {
        #expect(encode(MD.block(.paragraph, MD.run(symbol), MD.run("\"b\"", .bold), MD.run(symbol)))
            == "\(symbol)<!-- -->**\"b\"**<!-- -->\(symbol)")
    }

    @Test func boldAndItalicOpenSeparatelyWhenTheInnerOneReopens() {
        #expect(encode(MD.block(
            .paragraph, MD.run("+", .bold, .italic), MD.run(" ~", .bold), MD.run("+", .bold, .italic)
        )) == "**<!-- -->*+* \\~*+***")
    }

    @Test func edgeWhitespaceMovesOutsideTheMarks() {
        #expect(encode(MD.block(.paragraph, MD.run("a "), MD.run("b ", .bold), MD.run("c"))) == "a **b** c")
    }

    @Test func softBreaks() {
        #expect(encode(Sem.block("a\u{2028}b")) == "a\\\nb")
        #expect(encode(Sem.block("a\u{2028}b", ul0)) == "- a\\\n  b")
        #expect(encode(Sem.block("a\u{2028}b", .blockquote)) == "> a\\\n> b")
        #expect(encode(Sem.block("a\u{2028}b", .heading(1))) == "# a b")
        #expect(encode(Sem.block("a\u{2028}# b")) == "a\\\n\\# b")
        #expect(encode(Sem.block("\u{2028}a\u{2028}")) == "a")
    }

    @Test func underlineAndColorAreDroppedTextKept() {
        var colored = MD.run("a", .underline)
        colored.textColor = RichTextColor(red: 255, green: 0, blue: 0)
        #expect(encode(MD.block(.paragraph, colored)) == "a")
    }
}
