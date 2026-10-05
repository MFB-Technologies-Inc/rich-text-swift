// EngineCore+Insert.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
import RichTextCore

extension EngineCore {
    /// Replaces the selection with a semantic fragment, such as a decoded rich
    /// paste. Pure, like `insertNewline`, so the splice rule is
    /// covered by `swift test` and the platform adapter only has to hand the
    /// fragment over.
    ///
    /// The fragment's text and inline formatting land as-is. Block roles
    /// follow one rule: pasting never retypes text the user did not select,
    /// the same rule `insertNewline` follows for a surviving tail.
    ///
    /// | Block in the result | Role |
    /// |---|---|
    /// | Starts with text from before the selection | That text's block role |
    /// | Ends with text from after the selection | That text's block role |
    /// | Made only of fragment text | The fragment block's own role |
    ///
    /// A block that has both the surviving head and tail (a one-block
    /// fragment pasted mid-block) takes the head's role. One exception to the
    /// last row: a lone fragment paragraph that fills its block entirely
    /// takes the block's existing role, so pasting prose into an empty list
    /// item or over a selected heading reads like typing it.
    static func insert(
        _ fragment: AttributedString,
        in text: AttributedString,
        selection: TextSelection,
        typingAttributes: TypingAttributes
    ) -> EditResult {
        let fragment = bareSeparators(in: normalizingDefaultColor(fragment))
        guard !fragment.characters.isEmpty else {
            return EditResult(text: text, selection: selection, typingAttributes: typingAttributes)
        }

        var result = text
        let insertionRange = TextOffsets.range(selection, in: result)
        // Resolved from where the splice lands, not the raw requested offsets,
        // so a selection bound inside a character still lines up (as in
        // `insertNewline`).
        let lower = TextOffsets.offset(of: insertionRange.lowerBound, in: result)
        let upper = TextOffsets.offset(of: insertionRange.upperBound, in: result)

        let headBlock = BlockScanner.blocks(of: text, intersecting: .caret(at: lower)).first
            ?? DocumentBlock(location: 0, length: 0, style: .paragraph)
        let tailBlock = BlockScanner.blocks(of: text, intersecting: .caret(at: upper)).first ?? headBlock
        let keepsHead = lower > headBlock.location
        let keepsTail = upper < tailBlock.location + tailBlock.length
        // An empty block's role lives in the pending typing attribute.
        let hostStyle = (headBlock.isEmpty ? typingAttributes.blockStyle : nil) ?? headBlock.style

        result.replaceSubrange(insertionRange, with: fragment)

        let fragmentBlocks = BlockScanner.blocks(of: fragment)
        let resultBlocks = BlockScanner.blocks(of: result)
        let first = resultBlocks.firstIndex { $0.location == headBlock.location } ?? 0
        let last = fragmentBlocks.count - 1
        var caretBlockStyle: BlockStyle?
        for (offset, fragmentBlock) in fragmentBlocks.enumerated() {
            let style: BlockStyle = if offset == 0, keepsHead {
                headBlock.style
            } else if offset == last, keepsTail {
                tailBlock.style
            } else if last == 0, fragmentBlock.style == .paragraph {
                hostStyle
            } else {
                fragmentBlock.style
            }
            let block = resultBlocks[first + offset]
            if block.isEmpty {
                caretBlockStyle = offset == last ? style : nil
            } else {
                let range = TextOffsets.range(TextSelection(location: block.location, length: block.length), in: result)
                result[range].blockStyle = style
            }
        }

        let caret = TextSelection.caret(at: lower + TextOffsets.length(of: fragment))
        var typing = EngineCore.typingAttributes(at: caret, in: result)
        // A fragment ending in a newline leaves the caret in an empty block,
        // which can only hold its role as a pending style.
        typing.blockStyle = caretBlockStyle
        return EditResult(text: result, selection: caret, typingAttributes: typing)
    }

    /// `fragment` with inline attributes removed from every `"\n"`, and
    /// block style removed when that newline forms an empty block. Both are
    /// required for `decode(encode(x)) == x`.
    static func bareSeparators(in fragment: AttributedString) -> AttributedString {
        var result = AttributedString()
        for run in fragment.runs {
            let slice = fragment[run.range]
            var pieceStart = slice.startIndex
            var index = slice.startIndex
            while index < slice.endIndex {
                let next = slice.characters.index(after: index)
                if slice.characters[index] == "\n" {
                    result += AttributedString(slice[pieceStart ..< index])
                    var separator = AttributedString("\n")
                    let startsEmptyBlock = index == fragment.startIndex
                        || fragment.characters[fragment.characters.index(before: index)] == "\n"
                    if !startsEmptyBlock {
                        separator.blockStyle = slice.blockStyle
                    }
                    result += separator
                    pieceStart = next
                }
                index = next
            }
            result += AttributedString(slice[pieceStart ..< slice.endIndex])
        }
        return result
    }
}
