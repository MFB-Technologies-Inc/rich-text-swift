// BlockScannerEffectiveBlocksTests.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
import RichTextCore
@testable import RichTextEngine
import Testing

/// `effectiveBlocks` is the rendering counterpart to the pending block style: a
/// pending block style (held in `TypingAttributes.blockStyle` because
/// Foundation cannot attribute zero-length content) is substituted onto the
/// caret's own empty block for rendering purposes only — never written back
/// into the document. See `BlockScanner.effectiveBlocks` for the contract.
struct BlockScannerEffectiveBlocksTests {
    @Test func substitutesThePendingStyleOnTheCaretsEmptyBlock() {
        var doc = Sem.block("one", .listItem(.ordered, depth: 0))
        doc += AttributedString("\n")
        // "one\n" -> block 0 is "one" (listItem), block 1 is the trailing
        // empty paragraph the caret now sits in.
        let blocks = BlockScanner.effectiveBlocks(
            of: doc,
            selection: .caret(at: 4),
            pendingBlockStyle: .listItem(.ordered, depth: 0)
        )
        #expect(blocks.count == 2)
        #expect(blocks[1].isEmpty)
        #expect(blocks[1].style == .listItem(.ordered, depth: 0))
    }

    @Test func neverOverridesANonEmptyBlock() {
        let doc = Sem.block("one")
        let blocks = BlockScanner.effectiveBlocks(
            of: doc,
            selection: .caret(at: 1),
            pendingBlockStyle: .listItem(.ordered, depth: 0)
        )
        #expect(blocks == BlockScanner.blocks(of: doc))
    }

    @Test func noPendingStyleLeavesTheResultIdenticalToBlocksOf() {
        var doc = Sem.block("one", .listItem(.ordered, depth: 0))
        doc += AttributedString("\n")
        let blocks = BlockScanner.effectiveBlocks(of: doc, selection: .caret(at: 4), pendingBlockStyle: nil)
        #expect(blocks == BlockScanner.blocks(of: doc))
    }

    @Test func aCaretInADifferentBlockDoesNotAffectTheEmptyOne() {
        var doc = Sem.block("one", .listItem(.ordered, depth: 0))
        doc += AttributedString("\n")
        // Caret still sits in block 0 ("one"); a pending style existing
        // elsewhere (unusual, but the substitution must key off the caret's
        // own block, never "is there an empty block anywhere in the doc").
        let blocks = BlockScanner.effectiveBlocks(
            of: doc,
            selection: .caret(at: 1),
            pendingBlockStyle: .listItem(.ordered, depth: 0)
        )
        #expect(blocks[1].style == .paragraph)
    }
}
