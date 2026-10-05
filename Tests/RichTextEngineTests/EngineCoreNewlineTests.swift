// EngineCoreNewlineTests.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
import RichTextCore
@testable import RichTextEngine
import Testing

struct EngineCoreNewlineTests {
    private func newline(
        _ text: AttributedString,
        _ selection: TextSelection,
        typing: TypingAttributes = TypingAttributes()
    ) -> EditResult {
        EngineCore.insertNewline(in: text, selection: selection, typingAttributes: typing)
    }

    private func styles(_ text: AttributedString) -> [BlockStyle] {
        BlockScanner.blocks(of: text).map(\.style)
    }

    @Test func returnAtTheEndOfAParagraphMakesAnotherParagraph() {
        let result = newline(Sem.block("abc"), .caret(at: 3))
        #expect(String(result.text.characters) == "abc\n")
        #expect(result.selection == .caret(at: 4))
        #expect(result.typingAttributes.blockStyle == .paragraph)
    }

    @Test func returnAtTheEndOfAListItemContinuesTheList() {
        let doc = Sem.block("one", .listItem(.unordered, depth: 0))
        let result = newline(doc, .caret(at: 3))
        #expect(result.typingAttributes.blockStyle == .listItem(.unordered, depth: 0))
        // Typing into the new block lands the marker there.
        #expect(styles(result.text) == [.listItem(.unordered, depth: 0), .paragraph])
    }

    @Test func continuingAListPreservesKindAndDepth() {
        let doc = Sem.block("one", .listItem(.ordered, depth: 2))
        let result = newline(doc, .caret(at: 3))
        #expect(result.typingAttributes.blockStyle == .listItem(.ordered, depth: 2))
    }

    @Test func returnInAnEmptyListItemLeavesTheList() {
        // The pending role IS the empty block's role (Foundation cannot
        // attribute zero-length content), so leaving the list means clearing it
        // — and no newline is inserted, which is the standard editor behavior.
        var typing = TypingAttributes()
        typing.blockStyle = .listItem(.unordered, depth: 0)
        let result = newline(AttributedString(""), .caret(at: 0), typing: typing)
        #expect(result.text.characters.isEmpty)
        #expect(result.selection == .caret(at: 0))
        #expect(result.typingAttributes.blockStyle == nil)
    }

    @Test func returnInAnEmptyListItemMidDocumentLeavesTheListWithoutSplitting() {
        var doc = Sem.block("one", .listItem(.unordered, depth: 0))
        doc += AttributedString("\n")
        var typing = TypingAttributes()
        typing.blockStyle = .listItem(.unordered, depth: 0)
        let result = newline(doc, .caret(at: 4), typing: typing)
        #expect(String(result.text.characters) == "one\n")
        #expect(result.typingAttributes.blockStyle == nil)
    }

    @Test func returnAtTheEndOfAHeadingStartsAParagraph() {
        let result = newline(Sem.block("Title", .heading(1)), .caret(at: 5))
        #expect(result.typingAttributes.blockStyle == .paragraph)
        #expect(styles(result.text) == [.heading(1), .paragraph])
    }

    @Test func splittingAHeadingMidwayKeepsBothHalvesHeadings() {
        let result = newline(Sem.block("Title", .heading(2)), .caret(at: 2))
        #expect(String(result.text.characters) == "Ti\ntle")
        #expect(styles(result.text) == [.heading(2), .heading(2)])
        #expect(result.selection == .caret(at: 3))
    }

    @Test func splittingAListItemMidwayMakesTwoItems() {
        let result = newline(Sem.block("onetwo", .listItem(.ordered, depth: 1)), .caret(at: 3))
        #expect(String(result.text.characters) == "one\ntwo")
        #expect(styles(result.text) == [.listItem(.ordered, depth: 1), .listItem(.ordered, depth: 1)])
    }

    @Test func splittingAParagraphMakesTwoParagraphs() {
        let result = newline(Sem.block("onetwo"), .caret(at: 3))
        #expect(styles(result.text) == [.paragraph, .paragraph])
    }

    @Test func returnReplacesASelection() {
        let result = newline(Sem.block("abcdef"), TextSelection(location: 1, length: 3))
        #expect(String(result.text.characters) == "a\nef")
        #expect(result.selection == .caret(at: 2))
    }

    @Test func theInsertedNewlineCarriesNoInlineAttributes() {
        // A decorated separator breaks decode(encode(x)) == x.
        let doc = Sem.with(Sem.block("abc"), bold: true)
        var typing = TypingAttributes()
        typing.bold = true
        let result = newline(doc, .caret(at: 3), typing: typing)
        #expect(RichTextHTML.decode(RichTextHTML.encode(result.text)) == result.text)
    }

    @Test func inlineTypingAttributesCarryAcrossTheBreak() {
        var typing = TypingAttributes()
        typing.bold = true
        typing.textColor = RichTextColor(red: 255, green: 0, blue: 0)
        let result = newline(Sem.block("abc"), .caret(at: 3), typing: typing)
        #expect(result.typingAttributes.bold)
        #expect(result.typingAttributes.textColor == RichTextColor(red: 255, green: 0, blue: 0))
    }

    @Test func returnInAnEmptyDocumentAddsABlock() {
        let result = newline(AttributedString(""), .caret(at: 0))
        #expect(String(result.text.characters) == "\n")
        #expect(result.selection == .caret(at: 1))
    }

    @Test func returnAtTheStartOfABlockPushesItDown() {
        let result = newline(Sem.block("abc", .heading(1)), .caret(at: 0))
        #expect(String(result.text.characters) == "\nabc")
        // The text kept its role; the new empty first block cannot carry one.
        #expect(styles(result.text) == [.paragraph, .heading(1)])
        #expect(result.selection == .caret(at: 1))
    }

    @Test func splitBlocksSurviveASerializationRoundTrip() {
        let doc = Sem.doc(Sem.block("Title", .heading(1)), Sem.block("one", .listItem(.unordered, depth: 0)))
        let result = newline(doc, .caret(at: 9))
        #expect(RichTextHTML.decode(RichTextHTML.encode(result.text)) == result.text)
    }

    // MARK: - Bug 1: selections spanning a block boundary

    @Test func aSelectionSpanningTheBlockBoundaryMergesThenSplitsInTheOriginalRole() {
        // "AB\nCD": "AB" is a heading, "CD" is a list item. Selecting (1, 3)
        // deletes "B\nC" — merging "A" and "D" into one heading block — so
        // Return there is a mid-heading split, not a transition to paragraph.
        let doc = Sem.doc(Sem.block("AB", .heading(1)), Sem.block("CD", .listItem(.unordered, depth: 0)))
        let result = newline(doc, TextSelection(location: 1, length: 3))
        #expect(String(result.text.characters) == "A\nD")
        #expect(styles(result.text) == [.heading(1), .heading(1)])
    }

    @Test func aSelectionCoveringAWholeBlockPlusItsSeparatorLeavesCDUnderItsOwnRole() {
        // Selecting all of "AB" plus its trailing separator annihilates "AB"
        // entirely — not one of its characters survives — so "CD" (untouched
        // by the selection) must keep its own role, not inherit "AB"'s.
        let doc = Sem.doc(Sem.block("AB", .heading(1)), Sem.block("CD", .listItem(.unordered, depth: 0)))
        let result = newline(doc, TextSelection(location: 0, length: 3))
        #expect(String(result.text.characters) == "\nCD")
        #expect(styles(result.text) == [.paragraph, .listItem(.unordered, depth: 0)])
    }

    @Test func annihilatingTheCaretBlockEntirelyKeepsTheSurvivingBlocksOwnRole() {
        // "Title\none": selecting all of "Title" plus its separator (0, 6)
        // touches not one character of "one" — nothing of the caret block
        // ("Title") survives either — so "one" must stay a list item, not be
        // retyped into a heading just because the caret started there.
        let doc = Sem.doc(Sem.block("Title", .heading(1)), Sem.block("one", .listItem(.unordered, depth: 0)))
        let result = newline(doc, TextSelection(location: 0, length: 6))
        #expect(String(result.text.characters) == "\none")
        #expect(styles(result.text) == [.paragraph, .listItem(.unordered, depth: 0)])
    }

    @Test func aSelectionFromABlocksStartIntoTheMiddleOfTheNextBlockKeepsTheNextBlocksRoleOnItsPartialSurvivor() {
        // "AB\nCD": selecting (0, 4) removes "AB\nC" in full — "AB" is
        // annihilated and so is "C" — leaving only "D", a partial survivor of
        // "CD". Since "D" is literally CD's own untouched tail, it must carry
        // CD's role (list item), not AB's (heading).
        let doc = Sem.doc(Sem.block("AB", .heading(1)), Sem.block("CD", .listItem(.unordered, depth: 0)))
        let result = newline(doc, TextSelection(location: 0, length: 4))
        #expect(String(result.text.characters) == "\nD")
        #expect(styles(result.text) == [.paragraph, .listItem(.unordered, depth: 0)])
    }

    // MARK: - Bug 2: caret placement with multi-UTF-16-unit characters

    @Test func returnInsideAMultiUTF16UnitCharacterPlacesTheCaretAfterTheResolvedNewline() {
        // "A👍B": the emoji occupies UTF-16 offsets 1-3. A caret requested at
        // offset 2 (mid-emoji) resolves forward to offset 3, so the newline
        // lands at 3..<4 and the caret must come back as 4, not 3.
        let doc = Sem.block("A👍B")
        let result = newline(doc, .caret(at: 2))
        #expect(String(result.text.characters) == "A👍\nB")
        #expect(result.selection == .caret(at: 4))
    }

    // MARK: - Empty heading / paragraph (only empty-list-item was covered before)

    @Test func returnInAnEmptyHeadingInsertsANewlineLikeAnyOtherBlock() {
        var typing = TypingAttributes()
        typing.blockStyle = .heading(2)
        let result = newline(AttributedString(""), .caret(at: 0), typing: typing)
        #expect(String(result.text.characters) == "\n")
        #expect(result.selection == .caret(at: 1))
        #expect(result.typingAttributes.blockStyle == .paragraph)
    }

    @Test func returnInAnEmptyParagraphInsertsANewlineLikeAnyOtherBlock() {
        var typing = TypingAttributes()
        typing.blockStyle = .paragraph
        let result = newline(AttributedString(""), .caret(at: 0), typing: typing)
        #expect(String(result.text.characters) == "\n")
        #expect(result.selection == .caret(at: 1))
        #expect(result.typingAttributes.blockStyle == .paragraph)
    }

    // MARK: - Blockquote (F5)

    //
    // Blockquote follows the **heading** rule, not the paragraph one:
    //   - Return at the END of a quote exits to a paragraph. There is no
    //     toolbar control for blockquote in v1, so if Return continued the
    //     quote a user who landed in an imported quote would have no way out
    //     of it at all.
    //   - A MID-quote split keeps both halves quoted, exactly as a mid-heading
    //     split keeps both halves headings — the text was deliberately quoted,
    //     and silently unquoting its tail is data loss on edit.

    @Test func returnAtTheEndOfABlockquoteMakesAParagraph() {
        let result = newline(Sem.block("quoted", .blockquote), .caret(at: 6))
        #expect(String(result.text.characters) == "quoted\n")
        #expect(result.selection == .caret(at: 7))
        #expect(result.typingAttributes.blockStyle == .paragraph)
    }

    @Test func splittingABlockquoteKeepsBothHalvesQuoted() {
        let result = newline(Sem.block("quoted", .blockquote), .caret(at: 3))
        #expect(String(result.text.characters) == "quo\nted")
        #expect(styles(result.text) == [.blockquote, .blockquote])
    }

    @Test func returnInAnEmptyBlockquoteInsertsANewlineAndExitsTheQuote() {
        var typing = TypingAttributes()
        typing.blockStyle = .blockquote
        let result = newline(AttributedString(""), .caret(at: 0), typing: typing)
        #expect(String(result.text.characters) == "\n")
        #expect(result.selection == .caret(at: 1))
        #expect(result.typingAttributes.blockStyle == .paragraph)
    }

    @Test func blockquoteSplitSurvivesASerializationRoundTrip() {
        let result = newline(Sem.block("quoted", .blockquote), .caret(at: 3))
        #expect(RichTextHTML.decode(RichTextHTML.encode(result.text)) == result.text)
    }
}
