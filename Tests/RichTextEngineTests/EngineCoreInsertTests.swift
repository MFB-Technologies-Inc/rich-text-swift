// EngineCoreInsertTests.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
import RichTextCore
@testable import RichTextEngine
import Testing

struct EngineCoreInsertTests {
    private func insert(
        _ fragment: AttributedString,
        into text: AttributedString,
        _ selection: TextSelection,
        typing: TypingAttributes = TypingAttributes()
    ) -> EditResult {
        EngineCore.insert(fragment, in: text, selection: selection, typingAttributes: typing)
    }

    private func styles(_ text: AttributedString) -> [BlockStyle] {
        BlockScanner.blocks(of: text).map(\.style)
    }

    // MARK: - One-block fragments

    @Test func aOneBlockFragmentMidParagraphTakesTheParagraphsRole() {
        let fragment = Sem.with(Sem.block("XY", .heading(1)), bold: true)
        let result = insert(fragment, into: Sem.block("abcd"), .caret(at: 2))
        #expect(String(result.text.characters) == "abXYcd")
        #expect(styles(result.text) == [.paragraph])
        #expect(result.selection == .caret(at: 4))
    }

    @Test func aOneBlockFragmentKeepsItsInlineFormatting() {
        let fragment = Sem.with(Sem.block("XY"), bold: true)
        let result = insert(fragment, into: Sem.block("abcd"), .caret(at: 2))
        let bold = result.text.runs.map { String(result.text[$0.range].characters) + ":\($0.bold == true)" }
        #expect(bold == ["ab:false", "XY:true", "cd:false"])
    }

    @Test func aOneBlockFragmentAtTheStartOfAHeadingLeavesItAHeading() {
        let result = insert(Sem.block("XY"), into: Sem.block("Title", .heading(2)), .caret(at: 0))
        #expect(String(result.text.characters) == "XYTitle")
        #expect(styles(result.text) == [.heading(2)])
    }

    @Test func aOneBlockFragmentIntoAnEmptyDocumentKeepsItsOwnRole() {
        let result = insert(Sem.block("Title", .heading(1)), into: AttributedString(""), .caret(at: 0))
        #expect(styles(result.text) == [.heading(1)])
    }

    @Test func aParagraphFragmentIntoAnEmptyListItemBecomesAListItem() {
        // The empty block's role is pending in the typing attributes;
        // pasting plain prose there should read like typing it.
        var typing = TypingAttributes()
        typing.blockStyle = .listItem(.unordered, depth: 0)
        let doc = Sem.doc(Sem.block("one", .listItem(.unordered, depth: 0)), AttributedString(""))
        let result = insert(Sem.block("two"), into: doc, .caret(at: 4), typing: typing)
        #expect(String(result.text.characters) == "one\ntwo")
        #expect(styles(result.text) == [.listItem(.unordered, depth: 0), .listItem(.unordered, depth: 0)])
    }

    // MARK: - Multi-block fragments

    @Test func aMultiBlockFragmentMidBlockLeavesTheSurvivingHeadAndTailTheirRole() {
        let fragment = Sem.doc(Sem.block("A", .heading(1)), Sem.block("B", .blockquote), Sem.block("C", .heading(3)))
        let doc = Sem.block("head|tail", .listItem(.ordered, depth: 1))
        let result = insert(fragment, into: doc, TextSelection(location: 4, length: 1))
        #expect(String(result.text.characters) == "headA\nB\nCtail")
        #expect(styles(result.text) == [
            .listItem(.ordered, depth: 1),
            .blockquote,
            .listItem(.ordered, depth: 1),
        ])
        #expect(result.selection == .caret(at: 9))
    }

    @Test func aMultiBlockFragmentReplacingWholeBlocksKeepsEveryFragmentRole() {
        let fragment = Sem.doc(Sem.block("A", .heading(1)), Sem.block("B", .blockquote))
        let doc = Sem.doc(Sem.block("x"), Sem.block("gone"), Sem.block("y"))
        let result = insert(fragment, into: doc, TextSelection(location: 2, length: 4))
        #expect(String(result.text.characters) == "x\nA\nB\ny")
        #expect(styles(result.text) == [.paragraph, .heading(1), .blockquote, .paragraph])
    }

    @Test func theSurvivingTailKeepsTheRoleOfTheBlockItCameFrom() {
        // The selection runs from mid-paragraph into a heading, so the text
        // after it is heading text and stays heading text.
        let fragment = Sem.doc(Sem.block("A"), Sem.block("B"))
        let doc = Sem.doc(Sem.block("abc"), Sem.block("Title", .heading(1)))
        let result = insert(fragment, into: doc, TextSelection(location: 1, length: 5))
        #expect(String(result.text.characters) == "aA\nBtle")
        #expect(styles(result.text) == [.paragraph, .heading(1)])
    }

    // MARK: - Typing attributes and edge cases

    @Test func theCaretAfterABoldFragmentTypesBold() {
        let fragment = Sem.with(Sem.block("XY"), bold: true)
        let result = insert(fragment, into: Sem.block("abcd"), .caret(at: 2))
        #expect(result.typingAttributes.bold)
        #expect(result.typingAttributes.blockStyle == nil)
    }

    @Test func anEmptyFragmentChangesNothing() {
        let doc = Sem.block("abc", .heading(1))
        var typing = TypingAttributes()
        typing.italic = true
        let result = insert(AttributedString(""), into: doc, .caret(at: 1), typing: typing)
        #expect(result == EditResult(text: doc, selection: .caret(at: 1), typingAttributes: typing))
    }

    @Test func fragmentSeparatorsCarryNoInlineAttributes() throws {
        // decode(encode(x)) == x depends on bare separators, and a fragment
        // may not come from the HTML decoder.
        let fragment = Sem.with(Sem.doc(Sem.block("A"), Sem.block("B")), bold: true)
        let result = insert(fragment, into: AttributedString(""), .caret(at: 0))
        let newline = try #require(result.text.characters.firstIndex(of: "\n"))
        let separator = result.text[newline ..< result.text.index(afterCharacter: newline)]
        #expect(separator.bold == nil)
    }

    @Test func aBlackFragmentColorIsDropped() {
        let fragment = Sem.with(Sem.block("A"), color: .black)
        let result = insert(fragment, into: Sem.block("x"), .caret(at: 1))
        #expect(String(result.text.characters) == "xA")
        #expect(result.text.runs.allSatisfy { $0.textColor == nil })
    }
}
