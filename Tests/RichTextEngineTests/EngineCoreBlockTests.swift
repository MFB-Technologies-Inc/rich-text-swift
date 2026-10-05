// EngineCoreBlockTests.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
import RichTextCore
@testable import RichTextEngine
import Testing

struct EngineCoreBlockTests {
    private func apply(
        _ command: FormatCommand,
        _ text: AttributedString,
        _ selection: TextSelection,
        typing: TypingAttributes = TypingAttributes()
    ) -> EditResult {
        EngineCore.apply(command, to: text, selection: selection, typingAttributes: typing)
    }

    private func styles(_ text: AttributedString) -> [BlockStyle] {
        BlockScanner.blocks(of: text).map(\.style)
    }

    @Test func setBlockStyleAppliesToTheCaretsBlockOnly() {
        let doc = Sem.doc(Sem.block("one"), Sem.block("two"))
        let result = apply(.setBlockStyle(.heading(2)), doc, .caret(at: 1))
        #expect(styles(result.text) == [.heading(2), .paragraph])
    }

    @Test func setBlockStyleAppliesToTheWholeBlockNotJustTheSelectedCharacters() {
        let result = apply(.setBlockStyle(.heading(1)), Sem.block("abcdef"), TextSelection(location: 2, length: 1))
        #expect(styles(result.text) == [.heading(1)])
        #expect(result.text.runs.count == 1)
    }

    @Test func setBlockStyleAppliesToEveryBlockTheSelectionTouches() {
        let doc = Sem.doc(Sem.block("one"), Sem.block("two"), Sem.block("three"))
        let result = apply(.setBlockStyle(.heading(3)), doc, TextSelection(location: 2, length: 4))
        #expect(styles(result.text) == [.heading(3), .heading(3), .paragraph])
    }

    @Test func blockCommandsPreserveTextAndSelection() {
        let doc = Sem.doc(Sem.block("one"), Sem.block("two"))
        let selection = TextSelection(location: 1, length: 5)
        let result = apply(.toggleHeading(1), doc, selection)
        #expect(String(result.text.characters) == "one\ntwo")
        #expect(result.selection == selection)
    }

    @Test func blockCommandsPreserveInlineFormatting() {
        let doc = Sem.with(Sem.block("abc"), bold: true, color: RichTextColor(red: 255, green: 0, blue: 0))
        let result = apply(.toggleHeading(2), doc, .caret(at: 1))
        let state = EngineCore.formatState(
            of: result.text,
            selection: TextSelection(location: 0, length: 3),
            typingAttributes: TypingAttributes()
        )
        #expect(state.bold == .on)
        #expect(state.textColor == RichTextColor(red: 255, green: 0, blue: 0))
        #expect(state.blockStyle == .heading(2))
    }

    @Test func toggleHeadingRevertsAnAlreadyMatchingBlockToParagraph() {
        let doc = Sem.block("Title", .heading(1))
        #expect(styles(apply(.toggleHeading(1), doc, .caret(at: 1)).text) == [.paragraph])
    }

    @Test func toggleHeadingSwitchesLevelRatherThanReverting() {
        let doc = Sem.block("Title", .heading(1))
        #expect(styles(apply(.toggleHeading(3), doc, .caret(at: 1)).text) == [.heading(3)])
    }

    @Test func toggleHeadingOnAPartiallyMatchingSelectionSetsThemAll() {
        let doc = Sem.doc(Sem.block("a", .heading(1)), Sem.block("b"))
        #expect(styles(apply(.toggleHeading(1), doc, TextSelection(location: 0, length: 3)).text) == [
            .heading(1),
            .heading(1),
        ])
    }

    @Test func toggleListMakesFlatListItems() {
        let doc = Sem.doc(Sem.block("one"), Sem.block("two"))
        let result = apply(.toggleList(.unordered), doc, TextSelection(location: 0, length: 7))
        #expect(styles(result.text) == [.listItem(.unordered, depth: 0), .listItem(.unordered, depth: 0)])
    }

    @Test func toggleListRevertsAMatchingListToParagraphs() {
        let doc = Sem.doc(
            Sem.block("one", .listItem(.ordered, depth: 0)),
            Sem.block("two", .listItem(.ordered, depth: 0))
        )
        #expect(styles(apply(.toggleList(.ordered), doc, TextSelection(location: 0, length: 7)).text) == [
            .paragraph,
            .paragraph,
        ])
    }

    @Test func toggleListChangesKindAndPreservesDepth() {
        let doc = Sem.block("item", .listItem(.unordered, depth: 2))
        #expect(styles(apply(.toggleList(.ordered), doc, .caret(at: 1)).text) == [.listItem(.ordered, depth: 2)])
    }

    @Test func toggleListRevertingANestedItemPreservesNothingButParagraph() {
        let doc = Sem.block("item", .listItem(.ordered, depth: 2))
        #expect(styles(apply(.toggleList(.ordered), doc, .caret(at: 1)).text) == [.paragraph])
    }

    @Test func toggleListOnAMixedSelectionMakesThemAllThatKind() {
        let doc = Sem.doc(Sem.block("a", .listItem(.unordered, depth: 0)), Sem.block("b", .heading(1)))
        let result = apply(.toggleList(.unordered), doc, TextSelection(location: 0, length: 3))
        #expect(styles(result.text) == [.listItem(.unordered, depth: 0), .listItem(.unordered, depth: 0)])
    }

    @Test func blockStyleOnAnEmptyBlockBecomesAPendingTypingAttribute() {
        // The Foundation zero-length limitation: nothing can carry the marker
        // yet, so it is held in typing attributes (M3 decision D13).
        let result = apply(.toggleHeading(1), AttributedString(""), .caret(at: 0))
        #expect(result.text.characters.isEmpty)
        #expect(result.typingAttributes.blockStyle == .heading(1))
        #expect(EngineCore.formatState(
            of: result.text,
            selection: result.selection,
            typingAttributes: result.typingAttributes
        ).blockStyle == .heading(1))
    }

    @Test func pendingBlockStyleTogglesOffAgain() {
        var typing = TypingAttributes()
        typing.blockStyle = .heading(1)
        let result = apply(.toggleHeading(1), AttributedString(""), .caret(at: 0), typing: typing)
        #expect(result.typingAttributes.blockStyle == .paragraph)
    }

    @Test func pendingStyleOnAnEmptyBlockInTheMiddleOfADocument() {
        var doc = Sem.block("abc")
        doc += AttributedString("\n\n")
        doc += Sem.block("def")
        let result = apply(.toggleList(.unordered), doc, .caret(at: 4))
        #expect(styles(result.text) == [.paragraph, .paragraph, .paragraph])
        #expect(result.typingAttributes.blockStyle == .listItem(.unordered, depth: 0))
    }

    @Test func settingANonEmptyBlockClearsAnyPendingStyle() {
        var typing = TypingAttributes()
        typing.blockStyle = .heading(1)
        let result = apply(.toggleList(.ordered), Sem.block("abc"), .caret(at: 1), typing: typing)
        #expect(result.typingAttributes.blockStyle == nil)
        #expect(styles(result.text) == [.listItem(.ordered, depth: 0)])
    }

    @Test func multiBlockSelectionSkipsEmptyBlocksButStylesTheRest() {
        var doc = Sem.block("abc")
        doc += AttributedString("\n\n")
        doc += Sem.block("def")
        let result = apply(.setBlockStyle(.heading(2)), doc, TextSelection(location: 0, length: 8))
        // The empty middle block cannot carry the marker and stays .paragraph.
        #expect(styles(result.text) == [.heading(2), .paragraph, .heading(2)])
    }

    @Test func styledBlocksSerializeThroughTheEncoder() {
        // The engine's writes must be exactly what the M2 encoder reads.
        let doc = Sem.doc(Sem.block("Title"), Sem.block("one"), Sem.block("two"))
        var result = apply(.toggleHeading(1), doc, .caret(at: 0))
        result = apply(.toggleList(.unordered), result.text, TextSelection(location: 6, length: 7))
        #expect(RichTextHTML.encode(result.text) == "<h1>Title</h1>\n<ul><li>one</li><li>two</li></ul>")
    }

    @Test func caretInlineToggleOnAnEmptyDocumentPreservesAPendingBlockStyle() {
        // Tapping H1 on a blank line (pending typingAttributes.blockStyle),
        // then Bold before typing, must not lose the H1 intent.
        var typing = TypingAttributes()
        typing.blockStyle = .heading(1)
        let result = apply(.toggleBold, AttributedString(""), .caret(at: 0), typing: typing)
        #expect(result.typingAttributes.blockStyle == .heading(1))
    }

    @Test func nonCollapsedSelectionOverOnlyEmptyBlocksClearsAnyPendingStyle() {
        // "abc\n\n\ndef": two empty blocks in the middle (offsets 4 and 5).
        // A non-collapsed selection has no caret, so a pending style left
        // over from some earlier command must not leak into the result.
        var doc = Sem.block("abc")
        doc += AttributedString("\n\n\n")
        doc += Sem.block("def")
        var typing = TypingAttributes()
        typing.blockStyle = .heading(1)
        let result = apply(.toggleList(.unordered), doc, TextSelection(location: 4, length: 2), typing: typing)
        #expect(result.typingAttributes.blockStyle == nil)
    }

    @Test func nonCollapsedSelectionOverASingleEmptyBlockClearsAnyPendingStyle() {
        var doc = Sem.block("abc")
        doc += AttributedString("\n\n")
        doc += Sem.block("def")
        var typing = TypingAttributes()
        typing.blockStyle = .heading(1)
        let result = apply(.toggleList(.unordered), doc, TextSelection(location: 4, length: 1), typing: typing)
        #expect(result.typingAttributes.blockStyle == nil)
    }
}
