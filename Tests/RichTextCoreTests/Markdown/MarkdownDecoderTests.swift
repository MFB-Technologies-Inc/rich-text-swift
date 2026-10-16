// MarkdownDecoderTests.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
@testable import RichTextCore
import Testing

struct MarkdownDecoderTests {
    private let ul0 = BlockStyle.listItem(.unordered, depth: 0)

    private func decode(_ markdown: String) -> AttributedString {
        RichTextMarkdown.decode(markdown)
    }

    @Test func emptyInputIsAnEmptyDocument() {
        #expect(decode("") == AttributedString())
    }

    @Test func headingsAndParagraphs() {
        #expect(decode("# H\n\npara") == Sem.doc(Sem.block("H", .heading(1)), Sem.block("para")))
    }

    @Test func deeperHeadingsClampToH3() {
        #expect(decode("#### Deep") == Sem.block("Deep", .heading(3)))
    }

    @Test func inlineMarksIncludingNonCanonicalSpellings() {
        #expect(decode("**b** *i* ~~s~~ _u_ __v__") == MD.block(
            .paragraph,
            MD.run("b", .bold), MD.run(" "), MD.run("i", .italic), MD.run(" "),
            MD.run("s", .strikethrough), MD.run(" "), MD.run("u", .italic), MD.run(" "), MD.run("v", .bold)
        ))
    }

    @Test func plusBulletsAreUnorderedItems() {
        #expect(decode("+ a\n+ b") == Sem.doc(Sem.block("a", ul0), Sem.block("b", ul0)))
    }

    @Test func nestedListsCarryDepthAndKind() {
        #expect(decode("- a\n  - b\n    - c\n- d\n\n1. x\n   - y") == Sem.doc(
            Sem.block("a", ul0),
            Sem.block("b", .listItem(.unordered, depth: 1)),
            Sem.block("c", .listItem(.unordered, depth: 2)),
            Sem.block("d", ul0),
            Sem.block("x", .listItem(.ordered, depth: 0)),
            Sem.block("y", .listItem(.unordered, depth: 1))
        ))
    }

    @Test func blockquotes() {
        #expect(decode("> a\n> b") == Sem.block("a b", .blockquote))
        #expect(decode("> > nested") == Sem.block("nested", .blockquote))
        // List membership is the more specific role; the flat model holds one.
        #expect(decode("> - x") == Sem.block("x", ul0))
    }

    @Test func hardBreaksBecomeSoftLineBreaks() {
        #expect(decode("a\\\nb") == Sem.block("a\u{2028}b"))
        #expect(decode("a  \nb") == Sem.block("a\u{2028}b"))
    }

    @Test func emptyListItemsAreDropped() {
        #expect(decode("- a\n- \n- b") == Sem.doc(Sem.block("a", ul0), Sem.block("b", ul0)))
    }

    // MARK: Content outside the model keeps its text

    @Test func inlineCodeKeepsItsText() {
        #expect(decode("`code` x") == Sem.block("code x"))
    }

    @Test func codeBlockLinesBecomeParagraphs() {
        #expect(decode("```swift\nlet x\n\n  y\n```") == Sem.doc(Sem.block("let x"), Sem.block("  y")))
    }

    @Test func tableRowsBecomeParagraphs() {
        #expect(decode("| a | b |\n|---|---|\n| 1 | 2 |") == Sem.doc(Sem.block("a b"), Sem.block("1 2")))
    }

    @Test func imagesKeepAltTextAndLinksKeepTheirText() {
        #expect(decode("![alt](i.png) [t](https://x.com) <https://a.com>") == Sem.block("alt t https://a.com"))
    }

    @Test func rulesAreDropped() {
        #expect(decode("a\n\n---\n\nb") == Sem.doc(Sem.block("a"), Sem.block("b")))
    }

    @Test func taskListsKeepTheirBracketText() {
        #expect(decode("- [ ] task") == Sem.block("[ ] task", ul0))
    }

    @Test func inlineHTMLTagsAreDroppedAndTheirTextKept() {
        #expect(decode("a <u>b</u> c") == Sem.block("a b c"))
    }
}
