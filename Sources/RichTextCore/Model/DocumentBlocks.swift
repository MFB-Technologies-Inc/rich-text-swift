// DocumentBlocks.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation

/// The `\n`-delimited blocks of a semantic document, each with its role.
/// Shared by the HTML and Markdown encoders so both read roles the same way.
enum DocumentBlocks {
    struct Block {
        var slice: Range<AttributedString.Index>
        var style: BlockStyle
    }

    static func split(_ attr: AttributedString) -> [Block] {
        var blocks: [Block] = []
        var start = attr.startIndex
        var index = attr.startIndex
        func pushBlock(end: AttributedString.Index) {
            // Defaults to .paragraph for an empty slice because Foundation can't
            // carry a blockStyle attribute on zero-length content; see the matching
            // note in `HTMLDecoder.Builder.finish()`.
            let style = (start < attr.endIndex) ? (attr[start ..< end].blockStyle ?? .paragraph) : .paragraph
            blocks.append(Block(slice: start ..< end, style: style))
        }
        while index < attr.endIndex {
            if attr.characters[index] == "\n" {
                pushBlock(end: index)
                start = attr.index(afterCharacter: index)
            }
            index = attr.index(afterCharacter: index)
        }
        pushBlock(end: attr.endIndex)
        for index in blocks.indices.dropFirst().dropLast() where blocks[index].slice.isEmpty {
            if let role = BlockStyle.roleOfEmptyBlock(between: blocks[index - 1].style, and: blocks[index + 1].style) {
                blocks[index].style = role
            }
        }
        return blocks
    }
}
