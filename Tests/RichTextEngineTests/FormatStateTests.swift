// FormatStateTests.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
import RichTextCore
@testable import RichTextEngine
import Testing

struct FormatStateTests {
    private let red = RichTextColor(red: 255, green: 0, blue: 0)
    private let blue = RichTextColor(red: 0, green: 0, blue: 255)

    private func state(
        _ text: AttributedString,
        _ selection: TextSelection,
        typing: TypingAttributes = TypingAttributes()
    ) -> FormatState {
        EngineCore.formatState(of: text, selection: selection, typingAttributes: typing)
    }

    @Test func uniformBoldSelectionIsOn() {
        let doc = Sem.with(Sem.block("abc"), bold: true)
        #expect(state(doc, TextSelection(location: 0, length: 3)).bold == .on)
    }

    @Test func plainSelectionIsOff() {
        #expect(state(Sem.block("abc"), TextSelection(location: 0, length: 3)).bold == .off)
    }

    @Test func partiallyBoldSelectionIsMixed() {
        var doc = Sem.block("abcdef")
        let range = TextOffsets.range(TextSelection(location: 0, length: 3), in: doc)
        doc[range].bold = true
        #expect(state(doc, TextSelection(location: 0, length: 6)).bold == .mixed)
        // A selection confined to the bold half is not mixed.
        #expect(state(doc, TextSelection(location: 0, length: 3)).bold == .on)
        #expect(state(doc, TextSelection(location: 3, length: 3)).bold == .off)
    }

    @Test func eachInlineFlagIsReportedIndependently() {
        let doc = Sem.with(Sem.block("abc"), italic: true, strikethrough: true)
        let s = state(doc, TextSelection(location: 0, length: 3))
        #expect(s.italic == .on)
        #expect(s.strikethrough == .on)
        #expect(s.bold == .off)
        #expect(s.underline == .off)
    }

    @Test func uniformColorIsReportedAndNotMixed() {
        let doc = Sem.with(Sem.block("abc"), color: red)
        let s = state(doc, TextSelection(location: 0, length: 3))
        #expect(s.textColor == red)
        #expect(s.isTextColorMixed == false)
    }

    @Test func differingColorsAreMixed() {
        var doc = Sem.block("abcdef")
        doc[TextOffsets.range(TextSelection(location: 0, length: 3), in: doc)].textColor = red
        doc[TextOffsets.range(TextSelection(location: 3, length: 3), in: doc)].textColor = blue
        let s = state(doc, TextSelection(location: 0, length: 6))
        #expect(s.isTextColorMixed)
    }

    @Test func colorPresentInOnlyPartOfTheSelectionIsMixed() {
        var doc = Sem.block("abcdef")
        doc[TextOffsets.range(TextSelection(location: 0, length: 3), in: doc)].textColor = red
        #expect(state(doc, TextSelection(location: 0, length: 6)).isTextColorMixed)
    }

    @Test func boldSelectionSpanningTwoBlocksIsOnNotMixed() {
        // Two fully-bold paragraphs joined by an unstyled separator newline.
        // The newline run must not count against the tri-state, or every
        // multi-paragraph selection would report `.mixed` (Finding 1).
        let doc = Sem.doc(Sem.with(Sem.block("abc"), bold: true), Sem.with(Sem.block("def"), bold: true))
        #expect(state(doc, TextSelection(location: 0, length: 7)).bold == .on)
    }

    @Test func boldSelectionSpanningTwoBlocksOnlyOneBoldIsMixed() {
        let doc = Sem.doc(Sem.with(Sem.block("abc"), bold: true), Sem.block("def"))
        #expect(state(doc, TextSelection(location: 0, length: 7)).bold == .mixed)
    }

    @Test func uniformColorSelectionSpanningTwoBlocksIsNotMixed() {
        let doc = Sem.doc(Sem.with(Sem.block("abc"), color: red), Sem.with(Sem.block("def"), color: red))
        let s = state(doc, TextSelection(location: 0, length: 7))
        #expect(s.isTextColorMixed == false)
        #expect(s.textColor == red)
    }

    @Test func italicSelectionSpanningHeadingAndParagraphIsOnNotMixed() {
        // A `blockStyle` run boundary alone must not create "mixed" state.
        let doc = Sem.doc(
            Sem.with(Sem.block("Title", .heading(1)), italic: true),
            Sem.with(Sem.block("Body"), italic: true)
        )
        #expect(state(doc, TextSelection(location: 0, length: 10)).italic == .on)
    }

    @Test func selectionOfOnlyTheSeparatorNewlineIsAllOff() {
        // A selection consisting solely of newline separator(s) carries no
        // inline attributes to read: reported as all-`.off` with no color
        // (documented behavior, not derived from any run).
        let doc = Sem.doc(Sem.with(Sem.block("abc"), bold: true), Sem.with(Sem.block("def"), bold: true))
        let s = state(doc, TextSelection(location: 3, length: 1))
        #expect(s.bold == .off)
        #expect(s.italic == .off)
        #expect(s.underline == .off)
        #expect(s.strikethrough == .off)
        #expect(s.textColor == nil)
        #expect(s.isTextColorMixed == false)
    }

    @Test func uniformBlockStyleIsReported() {
        let doc = Sem.doc(Sem.block("Title", .heading(1)), Sem.block("Body"))
        #expect(state(doc, TextSelection(location: 0, length: 5)).blockStyle == .heading(1))
        #expect(state(doc, TextSelection(location: 6, length: 4)).blockStyle == .paragraph)
    }

    @Test func mixedBlockStylesReportNil() {
        let doc = Sem.doc(Sem.block("Title", .heading(1)), Sem.block("Body"))
        #expect(state(doc, TextSelection(location: 0, length: 10)).blockStyle == nil)
    }

    @Test func caretReadsInlineStateFromTypingAttributes() {
        let doc = Sem.block("abc")
        var typing = TypingAttributes()
        typing.bold = true
        typing.textColor = red
        let s = state(doc, .caret(at: 1), typing: typing)
        #expect(s.bold == .on)
        #expect(s.italic == .off)
        #expect(s.textColor == red)
        #expect(s.isTextColorMixed == false)
    }

    @Test func caretReadsBlockStyleFromTheContainingBlock() {
        let doc = Sem.doc(Sem.block("Title", .heading(2)), Sem.block("Body"))
        #expect(state(doc, .caret(at: 2)).blockStyle == .heading(2))
        #expect(state(doc, .caret(at: 8)).blockStyle == .paragraph)
    }

    @Test func pendingBlockStyleWinsForAnEmptyBlock() {
        // Empty document + a pending H1 (what the toolbar sets on a blank line).
        var typing = TypingAttributes()
        typing.blockStyle = .heading(1)
        #expect(state(AttributedString(""), .caret(at: 0), typing: typing).blockStyle == .heading(1))
    }

    @Test func typingAttributesDeriveFromTheCharacterBeforeTheCaret() {
        var doc = Sem.block("abcdef")
        doc[TextOffsets.range(TextSelection(location: 0, length: 3), in: doc)].bold = true
        // Caret right after the bold run inherits bold (standard editor behavior).
        #expect(EngineCore.typingAttributes(at: .caret(at: 3), in: doc).bold)
        // Caret at the very start looks forward instead.
        #expect(EngineCore.typingAttributes(at: .caret(at: 0), in: doc).bold)
        // Caret inside the plain run inherits nothing.
        #expect(EngineCore.typingAttributes(at: .caret(at: 5), in: doc).bold == false)
    }

    @Test func derivedTypingAttributesCarryTheBlockStyleOnlyForEmptyBlocks() {
        let doc = Sem.doc(Sem.block("Title", .heading(1)), Sem.block("Body"))
        // Non-empty block: the marker in the text is authoritative, no pending style.
        #expect(EngineCore.typingAttributes(at: .caret(at: 2), in: doc).blockStyle == nil)
        // Empty document: nothing can carry a marker, so none is derived either.
        #expect(EngineCore.typingAttributes(at: .caret(at: 0), in: AttributedString("")).blockStyle == nil)
    }
}
