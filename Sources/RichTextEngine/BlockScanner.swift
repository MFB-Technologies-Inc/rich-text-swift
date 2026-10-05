// BlockScanner.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
import RichTextCore

/// One `\n`-delimited block of the flat document, in UTF-16 offsets.
/// The range **excludes** the trailing newline, so it matches exactly what
/// `HTMLEncoder.splitBlocks` reads when serializing (M3 decision D11).
struct DocumentBlock: Equatable, Sendable {
    var location: Int
    var length: Int
    var style: BlockStyle

    var range: Range<Int> {
        location ..< (location + length)
    }

    var isEmpty: Bool {
        length == 0
    }
}

/// Splits the flat model into blocks. The `blockStyle` marker is the source of
/// truth; an empty block cannot carry one and reports `.paragraph` (the same
/// default the encoder uses — see M3 decision D13 for how editing works around it).
enum BlockScanner {
    static func blocks(of text: AttributedString) -> [DocumentBlock] {
        var result: [DocumentBlock] = []
        var blockStart = text.startIndex
        var blockStartOffset = 0
        var offset = 0
        var cursor = text.startIndex

        func push(end: AttributedString.Index, endOffset: Int) {
            let style = blockStart < end ? (text[blockStart ..< end].blockStyle ?? .paragraph) : .paragraph
            result.append(DocumentBlock(location: blockStartOffset, length: endOffset - blockStartOffset, style: style))
        }

        while cursor < text.endIndex {
            let character = text.characters[cursor]
            let next = text.index(afterCharacter: cursor)
            if character == "\n" {
                push(end: cursor, endOffset: offset)
                blockStart = next
                blockStartOffset = offset + 1
            }
            offset += String(character).utf16.count
            cursor = next
        }
        push(end: text.endIndex, endOffset: offset)
        for index in result.indices.dropFirst().dropLast() where result[index].isEmpty {
            if let role = BlockStyle.roleOfEmptyBlock(between: result[index - 1].style, and: result[index + 1].style) {
                result[index].style = role
            }
        }
        return result
    }

    /// Blocks the selection touches. A caret belongs to the block it sits in;
    /// a selection that merely ends at the start of the next block does not
    /// include that block (M3 decision D11).
    static func blocks(of text: AttributedString, intersecting selection: TextSelection) -> [DocumentBlock] {
        let all = blocks(of: text)
        let total = TextOffsets.length(of: text)
        let lower = min(selection.lowerBound, total)
        let upper = min(selection.upperBound, total)

        if lower == upper {
            let hit = all.filter { $0.location <= lower && lower <= $0.location + $0.length }
            return hit.isEmpty ? Array(all.suffix(1)) : Array(hit.suffix(1))
        }
        return all.filter { $0.location < upper && $0.location + $0.length >= lower }
    }

    /// Rendering counterpart to M3 decision D13: `blocks(of:)` reports
    /// `.paragraph` for an empty block because Foundation cannot attach an
    /// attribute to zero-length content, but while the caret sits in that
    /// block, its *actual* role is held as a pending style in
    /// `TypingAttributes.blockStyle`. This substitutes that pending style
    /// onto the caret's own empty block — purely for rendering (marker glyph,
    /// numbering, indent) — so an empty list item shows its bullet/number
    /// before any character exists to carry the role in the document.
    ///
    /// This must never be written back into the document: it only changes
    /// the `DocumentBlock` values handed to the rendering layer, never
    /// `text` itself. Every block other than the caret's own empty one is
    /// returned exactly as `blocks(of:)` reports it.
    static func effectiveBlocks(
        of text: AttributedString,
        selection: TextSelection,
        pendingBlockStyle: BlockStyle?
    ) -> [DocumentBlock] {
        var result = blocks(of: text)
        guard let pendingBlockStyle else { return result }
        guard let caretBlock = blocks(of: text, intersecting: selection).first, caretBlock.isEmpty else {
            return result
        }
        guard let index = result.firstIndex(where: { $0.location == caretBlock.location && $0.isEmpty }) else {
            return result
        }
        result[index].style = pendingBlockStyle
        return result
    }
}
