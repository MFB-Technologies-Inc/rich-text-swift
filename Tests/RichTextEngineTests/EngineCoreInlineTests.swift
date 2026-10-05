// EngineCoreInlineTests.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
import RichTextCore
@testable import RichTextEngine
import Testing

struct EngineCoreInlineTests {
    private let red = RichTextColor(red: 255, green: 0, blue: 0)
    private let blue = RichTextColor(red: 0, green: 0, blue: 255)
    private let black = RichTextColor(red: 0, green: 0, blue: 0)

    private func apply(
        _ command: FormatCommand,
        _ text: AttributedString,
        _ selection: TextSelection,
        typing: TypingAttributes = TypingAttributes()
    ) -> EditResult {
        EngineCore.apply(command, to: text, selection: selection, typingAttributes: typing)
    }

    private func state(_ result: EditResult) -> FormatState {
        EngineCore.formatState(of: result.text, selection: result.selection, typingAttributes: result.typingAttributes)
    }

    @Test func togglingBoldOnASelectionTurnsItOn() {
        let result = apply(.toggleBold, Sem.block("abcdef"), TextSelection(location: 0, length: 3))
        #expect(state(result).bold == .on)
        #expect(EngineCore.formatState(
            of: result.text,
            selection: TextSelection(location: 3, length: 3),
            typingAttributes: TypingAttributes()
        ).bold == .off)
    }

    @Test func togglingBoldTwiceRemovesTheAttributeEntirely() {
        let selection = TextSelection(location: 0, length: 3)
        let on = apply(.toggleBold, Sem.block("abcdef"), selection)
        let off = apply(.toggleBold, on.text, selection)
        #expect(state(off).bold == .off)
        // Removed, not set to false: the runs coalesce back to one.
        #expect(off.text.runs.count == 1)
        #expect(off.text == Sem.block("abcdef"))
    }

    @Test func togglingAMixedSelectionTurnsTheWholeThingOn() {
        var doc = Sem.block("abcdef")
        doc[TextOffsets.range(TextSelection(location: 0, length: 3), in: doc)].bold = true
        let whole = TextSelection(location: 0, length: 6)
        #expect(EngineCore.formatState(of: doc, selection: whole, typingAttributes: TypingAttributes()).bold == .mixed)
        #expect(state(apply(.toggleBold, doc, whole)).bold == .on)
    }

    @Test func eachToggleTouchesOnlyItsOwnAttribute() {
        var doc = Sem.block("abc")
        let selection = TextSelection(location: 0, length: 3)
        for command in [FormatCommand.toggleItalic, .toggleUnderline, .toggleStrikethrough] {
            doc = apply(command, doc, selection).text
        }
        let s = EngineCore.formatState(of: doc, selection: selection, typingAttributes: TypingAttributes())
        #expect(s.italic == .on)
        #expect(s.underline == .on)
        #expect(s.strikethrough == .on)
        #expect(s.bold == .off)
    }

    @Test func inlineToggleLeavesTheBlockMarkerIntact() {
        let doc = Sem.doc(Sem.block("Title", .heading(1)), Sem.block("Body"))
        let result = apply(.toggleBold, doc, TextSelection(location: 0, length: 5))
        #expect(BlockScanner.blocks(of: result.text).map(\.style) == [.heading(1), .paragraph])
    }

    @Test func inlineToggleAcrossABlockBoundaryKeepsBothMarkers() {
        let doc = Sem.doc(Sem.block("Title", .heading(1)), Sem.block("Body"))
        let result = apply(.toggleItalic, doc, TextSelection(location: 0, length: 10))
        #expect(BlockScanner.blocks(of: result.text).map(\.style) == [.heading(1), .paragraph])
        #expect(state(result).italic == .on)
    }

    @Test func crossBlockToggleAppliesToTextButNotTheSeparators() {
        let doc = Sem.doc(Sem.block("abc"), Sem.block("def"))
        let result = apply(.toggleBold, doc, TextSelection(location: 0, length: 7))
        #expect(state(result).bold == .on)
        #expect(RichTextHTML.encode(result.text) == "<p><b>abc</b></p>\n<p><b>def</b></p>")
        // The separator must stay unattributed, or the model stops surviving a
        // serialization round trip.
        #expect(RichTextHTML.decode(RichTextHTML.encode(result.text)) == result.text)
    }

    @Test func crossBlockColorSurvivesARoundTrip() {
        let doc = Sem.doc(Sem.block("Title", .heading(1)), Sem.block("body"))
        let result = apply(.setTextColor(red), doc, TextSelection(location: 0, length: 10))
        #expect(state(result).textColor == red)
        #expect(state(result).isTextColorMixed == false)
        #expect(RichTextHTML.decode(RichTextHTML.encode(result.text)) == result.text)
    }

    @Test func settingAndClearingColor() {
        let selection = TextSelection(location: 0, length: 3)
        let colored = apply(.setTextColor(red), Sem.block("abc"), selection)
        #expect(state(colored).textColor == red)

        let recolored = apply(.setTextColor(blue), colored.text, selection)
        #expect(state(recolored).textColor == blue)

        let cleared = apply(.setTextColor(nil), recolored.text, selection)
        #expect(state(cleared).textColor == nil)
        #expect(cleared.text.runs.count == 1)
        #expect(cleared.text == Sem.block("abc"))
    }

    @Test func inlineCommandsNeverChangeTheTextOrSelection() {
        let doc = Sem.block("abcdef")
        let selection = TextSelection(location: 1, length: 2)
        let result = apply(.toggleBold, doc, selection)
        #expect(String(result.text.characters) == "abcdef")
        #expect(result.selection == selection)
    }

    @Test func caretToggleUpdatesTypingAttributesOnly() {
        let doc = Sem.block("abc")
        let result = apply(.toggleBold, doc, .caret(at: 1))
        #expect(result.text == doc)
        #expect(result.typingAttributes.bold)
        #expect(state(result).bold == .on)

        let off = apply(.toggleBold, result.text, .caret(at: 1), typing: result.typingAttributes)
        #expect(off.typingAttributes.bold == false)
        #expect(state(off).bold == .off)
    }

    @Test func caretColorUpdatesTypingAttributesOnly() {
        let result = apply(.setTextColor(red), Sem.block("abc"), .caret(at: 1))
        #expect(result.text == Sem.block("abc"))
        #expect(result.typingAttributes.textColor == red)
    }

    // MARK: - Black is the absence of a text color

    //
    // Black is normalized to `nil` right here, at the command layer, so the
    // model never stores an explicit black run in the first place — the
    // ColorPicker control cannot express "no color", so picking black *is*
    // the remove gesture the user relies on.

    @Test func applyingBlackToASelectionLeavesNoColorAttribute() {
        let result = apply(.setTextColor(black), Sem.block("abc"), TextSelection(location: 0, length: 3))
        #expect(state(result).textColor == nil)
        #expect(result.text == Sem.block("abc"))
        #expect(RichTextHTML.encode(result.text) == "<p>abc</p>")
    }

    @Test func applyingBlackOverAnExistingColorClearsIt() {
        let selection = TextSelection(location: 0, length: 3)
        let colored = apply(.setTextColor(red), Sem.block("abc"), selection)
        #expect(state(colored).textColor == red)

        let cleared = apply(.setTextColor(black), colored.text, selection)
        #expect(state(cleared).textColor == nil)
        #expect(cleared.text == Sem.block("abc"))
    }

    @Test func applyingANonBlackColorStillWorks() {
        let result = apply(.setTextColor(red), Sem.block("abc"), TextSelection(location: 0, length: 3))
        #expect(state(result).textColor == red)
    }

    @Test func caretWithBlackAppliedLeavesTypingAttributesTextColorNil() {
        let result = apply(.setTextColor(black), Sem.block("abc"), .caret(at: 1))
        #expect(result.typingAttributes.textColor == nil)
    }

    @Test func settingBlackThroughTheEngineIsIndistinguishableFromNeverHavingAColor() {
        // The honest form of the round-trip invariant: a document that never
        // had a color, and one whose color was set to black *through the
        // engine* (never directly on the model), encode identically and both
        // round-trip. A document holding an explicit black run built by hand
        // (bypassing the engine) is exactly what this normalization makes
        // unreachable in practice, so it is not asserted here.
        let selection = TextSelection(location: 0, length: 3)
        let plain = Sem.block("abc")
        let wentThroughBlack = apply(.setTextColor(black), plain, selection).text

        #expect(wentThroughBlack == plain)
        #expect(RichTextHTML.encode(plain) == RichTextHTML.encode(wentThroughBlack))
        #expect(RichTextHTML.decode(RichTextHTML.encode(plain)) == plain)
        #expect(RichTextHTML.decode(RichTextHTML.encode(wentThroughBlack)) == wentThroughBlack)
    }

    @Test func caretToggleInAnEmptyDocumentWorks() {
        let result = apply(.toggleBold, AttributedString(""), .caret(at: 0))
        #expect(result.typingAttributes.bold)
        #expect(result.text.characters.isEmpty)
    }

    // MARK: - Selection spanning a genuinely empty block (Fix 5)

    //
    // "abc\n\ndef" has two separator newlines in a row, so the middle block
    // is empty — not just "a block boundary", but zero characters of actual
    // content between two "\n"s. `formatState`'s newline-skipping branch
    // (`slice.characters.allSatisfy { $0 == "\n" }`) is the most fragile
    // logic here; these tests stress it with a selection that
    // spans the whole document, empty block included, and check it behaves
    // exactly as the non-empty two-block case above (`togglingAMixedSelectionTurnsTheWholeThingOn`,
    // `crossBlockColorSurvivesARoundTrip`) rather than being thrown off by
    // the extra empty block or its doubled-up separator.

    @Test func formatStateOverAUniformlyBoldSelectionSpanningAnEmptyBlockReportsOn() {
        let doc = Sem.doc(Sem.with(Sem.block("abc"), bold: true), Sem.block(""), Sem.with(Sem.block("def"), bold: true))
        #expect(String(doc.characters) == "abc\n\ndef")
        let whole = TextSelection(location: 0, length: 8)
        #expect(EngineCore.formatState(of: doc, selection: whole, typingAttributes: TypingAttributes()).bold == .on)
    }

    @Test func formatStateOverAPartiallyBoldSelectionSpanningAnEmptyBlockReportsMixed() {
        let doc = Sem.doc(Sem.with(Sem.block("abc"), bold: true), Sem.block(""), Sem.block("def"))
        #expect(String(doc.characters) == "abc\n\ndef")
        let whole = TextSelection(location: 0, length: 8)
        #expect(EngineCore.formatState(of: doc, selection: whole, typingAttributes: TypingAttributes()).bold == .mixed)
    }

    @Test func formatStateOverASelectionSpanningAnEmptyBlockReportsOffWhenNoRunIsBold() {
        let doc = Sem.doc(Sem.block("abc"), Sem.block(""), Sem.block("def"))
        let whole = TextSelection(location: 0, length: 8)
        #expect(EngineCore.formatState(of: doc, selection: whole, typingAttributes: TypingAttributes()).bold == .off)
    }

    @Test func formatStateOverAUniformlyColoredSelectionSpanningAnEmptyBlockReportsThatColor() {
        let doc = Sem.doc(Sem.with(Sem.block("abc"), color: red), Sem.block(""), Sem.with(Sem.block("def"), color: red))
        let whole = TextSelection(location: 0, length: 8)
        let state = EngineCore.formatState(of: doc, selection: whole, typingAttributes: TypingAttributes())
        #expect(state.textColor == red)
        #expect(state.isTextColorMixed == false)
    }

    @Test func formatStateOverADifferentlyColoredSelectionSpanningAnEmptyBlockReportsMixed() {
        let doc = Sem.doc(
            Sem.with(Sem.block("abc"), color: red),
            Sem.block(""),
            Sem.with(Sem.block("def"), color: blue)
        )
        let whole = TextSelection(location: 0, length: 8)
        let state = EngineCore.formatState(of: doc, selection: whole, typingAttributes: TypingAttributes())
        #expect(state.isTextColorMixed)
        #expect(state.textColor == nil)
    }

    @Test func selectionToggleClearsStalePendingBlockStyle() {
        // A pending style is only meaningful for an empty block; once real text
        // is being formatted it must not linger.
        var typing = TypingAttributes()
        typing.blockStyle = .heading(1)
        let result = apply(.toggleBold, Sem.block("abc"), TextSelection(location: 0, length: 3), typing: typing)
        #expect(result.typingAttributes.blockStyle == nil)
    }
}
