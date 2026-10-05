// TextOffsetsTests.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
@testable import RichTextEngine
import Testing

struct TextOffsetsTests {
    /// "a🙂b" — the emoji is 2 UTF-16 units, so total length is 4.
    private let emoji = AttributedString("a🙂b")

    @Test func lengthCountsUTF16Units() {
        #expect(TextOffsets.length(of: AttributedString("")) == 0)
        #expect(TextOffsets.length(of: AttributedString("abc")) == 3)
        #expect(TextOffsets.length(of: emoji) == 4)
    }

    @Test func offsetAndIndexRoundTrip() {
        let text = AttributedString("abc\ndef")
        for offset in 0 ... 7 {
            let index = TextOffsets.index(at: offset, in: text)
            #expect(TextOffsets.offset(of: index, in: text) == offset)
        }
    }

    @Test func indexClampsOutOfRangeOffsets() {
        let text = AttributedString("abc")
        #expect(TextOffsets.index(at: -5, in: text) == text.startIndex)
        #expect(TextOffsets.index(at: 99, in: text) == text.endIndex)
    }

    @Test func offsetInsideACharacterRoundsUpToTheNextBoundary() {
        // Offset 2 is the trailing surrogate of the emoji; it must resolve to
        // the boundary after it, never to an invalid split.
        let index = TextOffsets.index(at: 2, in: emoji)
        #expect(TextOffsets.offset(of: index, in: emoji) == 3)
    }

    @Test func rangeSpansTheSelectedCharacters() {
        let text = AttributedString("abcdef")
        let range = TextOffsets.range(TextSelection(location: 2, length: 3), in: text)
        #expect(String(text[range].characters) == "cde")
    }

    @Test func rangeIsEmptyForACaret() {
        let text = AttributedString("abcdef")
        let range = TextOffsets.range(.caret(at: 3), in: text)
        #expect(range.isEmpty)
        #expect(TextOffsets.offset(of: range.lowerBound, in: text) == 3)
    }

    @Test func rangeClampsBeyondTheEnd() {
        let text = AttributedString("abc")
        let range = TextOffsets.range(TextSelection(location: 1, length: 99), in: text)
        #expect(String(text[range].characters) == "bc")
    }

    @Test func rangeHandlesEmptyText() {
        let text = AttributedString("")
        let range = TextOffsets.range(TextSelection(location: 4, length: 2), in: text)
        #expect(range.isEmpty)
        #expect(range.lowerBound == text.startIndex)
    }

    @Test func rangeRespectsEmojiBoundaries() {
        let range = TextOffsets.range(TextSelection(location: 1, length: 2), in: emoji)
        #expect(String(emoji[range].characters) == "🙂")
    }
}
