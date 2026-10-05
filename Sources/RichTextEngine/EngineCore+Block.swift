// EngineCore+Block.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
import RichTextCore

/// The three block-level operations. Narrows `FormatCommand` down to exactly
/// what `applyBlock` can act on, so the impossible state — an inline command
/// reaching the block path — is unrepresentable rather than guarded by a
/// `preconditionFailure`.
enum BlockOperation {
    case setStyle(BlockStyle)
    case toggleHeading(Int)
    case toggleList(ListKind)
}

extension EngineCore {
    /// Applies a block command to every block the selection touches
    /// (whole-block semantics, M3 decision D11). Text and selection are never
    /// changed — only the invisible marker.
    ///
    /// An *empty* block cannot carry the marker (Foundation cannot attribute
    /// zero-length content), so for a caret in an empty block the role is held
    /// as a pending typing attribute until characters exist (D13).
    ///
    /// A pending block style is meaningful only for a caret: it is the intent
    /// for characters not yet typed. A non-collapsed selection has no such
    /// intent, so the returned `typingAttributes.blockStyle` is always `nil`
    /// for one, regardless of which touched blocks were empty — it must not
    /// carry forward whatever pending style happened to be passed in.
    static func applyBlock(
        _ operation: BlockOperation,
        to text: AttributedString,
        selection: TextSelection,
        typingAttributes: TypingAttributes
    ) -> EditResult {
        let blocks = BlockScanner.blocks(of: text, intersecting: selection)
        var typing = typingAttributes
        var result = text

        for block in blocks {
            let target = targetStyle(for: operation, block: block, in: blocks, pending: typingAttributes.blockStyle)
            guard !block.isEmpty else {
                // Only a caret has a meaningful pending style; a multi-block
                // selection just can't style its empty members.
                if selection.isCollapsed {
                    typing.blockStyle = target
                }
                continue
            }
            let range = TextOffsets.range(TextSelection(location: block.location, length: block.length), in: result)
            result[range].blockStyle = target
            typing.blockStyle = nil
        }
        if !selection.isCollapsed {
            typing.blockStyle = nil
        }
        return EditResult(text: result, selection: selection, typingAttributes: typing)
    }

    /// The style a block should end up with. Heading/list commands are toggles:
    /// they revert to `.paragraph` only when *every* touched block already
    /// matches, so a partially-styled selection is normalized instead.
    private static func targetStyle(
        for operation: BlockOperation,
        block: DocumentBlock,
        in blocks: [DocumentBlock],
        pending: BlockStyle?
    ) -> BlockStyle {
        /// The role a block currently has, honoring a pending style for empty ones.
        func currentStyle(_ block: DocumentBlock) -> BlockStyle {
            (block.isEmpty ? pending : nil) ?? block.style
        }

        switch operation {
        case let .setStyle(style):
            return style

        case let .toggleHeading(level):
            let allMatch = blocks.allSatisfy { currentStyle($0) == .heading(level) }
            return allMatch ? .paragraph : .heading(level)

        case let .toggleList(kind):
            let allMatch = blocks.allSatisfy {
                if case let .listItem(itemKind, _) = currentStyle($0) {
                    return itemKind == kind
                }
                return false
            }
            if allMatch {
                return .paragraph
            }
            // Preserve existing nesting so decoded nested content survives a
            // kind change; new items start flat (M3 decision D12).
            if case let .listItem(_, depth) = currentStyle(block) {
                return .listItem(kind, depth: depth)
            }
            return .listItem(kind, depth: 0)
        }
    }
}
