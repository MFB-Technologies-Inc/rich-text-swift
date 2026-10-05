// LineEndingsTests.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
import RichTextCore
@testable import RichTextEngine
import Testing

struct LineEndingsTests {
    @Test func ingestMakesNormalizedCRLFSeparatorBare() throws {
        var document = AttributedString("a\r\nb")
        document.bold = true
        document.textColor = RichTextColor(red: 1, green: 0, blue: 0)
        document.blockStyle = .heading(1)

        let normalized = try #require(EngineCore.normalizedIngest(document, selection: .caret(at: 4)))
        #expect(String(normalized.text.characters) == "a\nb")
        #expect(normalized.selection == .caret(at: 3))
        let separator = normalized.text.characters.index(after: normalized.text.startIndex)
        let newline = normalized.text[separator ..< normalized.text.characters.index(after: separator)]
        #expect(newline.bold == nil)
        #expect(newline.textColor == nil)
        #expect(newline.blockStyle == .heading(1))
        #expect(RichTextHTML.decode(RichTextHTML.encode(normalized.text)) == normalized.text)
    }

    @Test func emptyCRLFBlockLosesItsStyleAndStaysStableOnReingest() throws {
        var document = AttributedString("\r\n")
        document.blockStyle = .heading(1)

        let normalized = try #require(EngineCore.normalizedIngest(document, selection: .caret(at: 2)))
        #expect(String(normalized.text.characters) == "\n")
        #expect(normalized.text.runs.first?.blockStyle == nil)
        #expect(RichTextHTML.decode(RichTextHTML.encode(normalized.text)) == normalized.text)
        #expect(EngineCore.normalizedIngest(normalized.text, selection: normalized.selection) == nil)
    }

    @Test func convertsCRLFAndLoneCRWithoutLosingFormatting() {
        var heading = AttributedString("a\r\n")
        heading.blockStyle = .heading(1)
        var paragraph = AttributedString("b\rc")
        paragraph.blockStyle = .paragraph
        heading.append(paragraph)

        let normalized = LineEndings.normalized(heading)

        #expect(String(normalized.characters) == "a\nb\nc")
        #expect(BlockScanner.blocks(of: normalized).map(\.style) == [.heading(1), .paragraph, .paragraph])
        #expect(normalized.runs.first?.blockStyle == .heading(1))
        #expect(LineEndings.normalized(normalized) == normalized)
    }

    @Test func joinsCRLFAcrossAttributeRuns() {
        var first = AttributedString("a\r")
        first.blockStyle = .heading(1)
        var second = AttributedString("\nb")
        second.blockStyle = .paragraph
        first.append(second)

        let normalized = LineEndings.normalized(first)

        #expect(String(normalized.characters) == "a\nb")
        #expect(BlockScanner.blocks(of: normalized).map(\.style) == [.heading(1), .paragraph])
        #expect(normalized.runs.first?.blockStyle == .heading(1))
    }

    @Test func mapsCaretAndSelectionAcrossCollapsedCRLFInUTF16() {
        let document = AttributedString("😀a\r\nb\rc\r\nd")

        #expect(LineEndings.selection(.caret(at: 5), mappedThrough: document) == .caret(at: 4))
        #expect(LineEndings.selection(.caret(at: 6), mappedThrough: document) == .caret(at: 5))
        #expect(
            LineEndings.selection(TextSelection(location: 3, length: 7), mappedThrough: document) == TextSelection(
                location: 3,
                length: 5
            )
        )
    }

    @Test func paragraphSeparatorAndNextLineSplitBlocksButLineSeparatorDoesNot() {
        let document = AttributedString("a\u{2029}b\u{0085}c\u{2028}d")

        let normalized = LineEndings.normalized(document)

        #expect(String(normalized.characters) == "a\nb\nc\u{2028}d")
        #expect(BlockScanner.blocks(of: normalized).count == 3)
        #expect(LineEndings.selection(.caret(at: 4), mappedThrough: document) == .caret(at: 4))
    }
}
