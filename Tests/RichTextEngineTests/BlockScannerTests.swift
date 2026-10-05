// BlockScannerTests.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
import RichTextCore
@testable import RichTextEngine
import Testing

struct BlockScannerTests {
    @Test func singleBlockDocument() {
        let blocks = BlockScanner.blocks(of: Sem.block("Hello", .heading(1)))
        #expect(blocks.count == 1)
        #expect(blocks[0].location == 0)
        #expect(blocks[0].length == 5)
        #expect(blocks[0].style == .heading(1))
    }

    @Test func blockRangesExcludeTheTrailingNewline() {
        let doc = Sem.doc(Sem.block("abc"), Sem.block("de", .heading(2)))
        let blocks = BlockScanner.blocks(of: doc)
        #expect(blocks.count == 2)
        #expect(blocks[0].range == 0 ..< 3)
        #expect(blocks[1].range == 4 ..< 6)
        #expect(blocks[1].style == .heading(2))
    }

    @Test func emptyDocumentIsOneEmptyParagraph() {
        let blocks = BlockScanner.blocks(of: AttributedString(""))
        #expect(blocks.count == 1)
        #expect(blocks[0].range == 0 ..< 0)
        #expect(blocks[0].isEmpty)
        #expect(blocks[0].style == .paragraph)
    }

    @Test func emptyBlockBetweenTwoBlocks() {
        // "abc\n\ndef" — the middle block is empty and cannot carry a marker,
        // so it reports .paragraph (matching HTMLEncoder.splitBlocks).
        var doc = Sem.block("abc")
        doc += AttributedString("\n\n")
        doc += Sem.block("def")
        let blocks = BlockScanner.blocks(of: doc)
        #expect(blocks.count == 3)
        #expect(blocks[1].range == 4 ..< 4)
        #expect(blocks[1].style == .paragraph)
        #expect(blocks[2].range == 5 ..< 8)
    }

    @Test func trailingNewlineProducesAFinalEmptyBlock() {
        var doc = Sem.block("abc")
        doc += AttributedString("\n")
        let blocks = BlockScanner.blocks(of: doc)
        #expect(blocks.count == 2)
        #expect(blocks[1].range == 4 ..< 4)
    }

    @Test func offsetsCountEmojiAsTwoUnits() {
        var doc = Sem.block("a🙂")
        doc += AttributedString("\n")
        doc += Sem.block("b")
        let blocks = BlockScanner.blocks(of: doc)
        #expect(blocks[0].range == 0 ..< 3)
        #expect(blocks[1].range == 4 ..< 5)
    }

    @Test func caretSelectsItsContainingBlock() {
        let doc = Sem.doc(Sem.block("abc"), Sem.block("def"))
        #expect(BlockScanner.blocks(of: doc, intersecting: .caret(at: 0)).map(\.range) == [0 ..< 3])
        #expect(BlockScanner.blocks(of: doc, intersecting: .caret(at: 3)).map(\.range) == [0 ..< 3])
        #expect(BlockScanner.blocks(of: doc, intersecting: .caret(at: 4)).map(\.range) == [4 ..< 7])
        #expect(BlockScanner.blocks(of: doc, intersecting: .caret(at: 7)).map(\.range) == [4 ..< 7])
    }

    @Test func selectionThroughTheNewlineDoesNotIncludeTheNextBlock() {
        let doc = Sem.doc(Sem.block("abc"), Sem.block("def"))
        // "abc\n" selected — the caret sits at the start of block 2 but no
        // character of it is selected.
        #expect(BlockScanner.blocks(of: doc, intersecting: TextSelection(location: 0, length: 4))
            .map(\.range) == [0 ..< 3])
        // One character into block 2 — both blocks.
        #expect(BlockScanner.blocks(of: doc, intersecting: TextSelection(location: 0, length: 5)).map(\.range) == [
            0 ..< 3,
            4 ..< 7,
        ])
    }

    @Test func selectionSpanningThreeBlocksIncludesTheEmptyMiddleOne() {
        var doc = Sem.block("abc")
        doc += AttributedString("\n\n")
        doc += Sem.block("def")
        let blocks = BlockScanner.blocks(of: doc, intersecting: TextSelection(location: 2, length: 4))
        #expect(blocks.map(\.range) == [0 ..< 3, 4 ..< 4, 5 ..< 8])
    }

    @Test func intersectingClampsBeyondTheEnd() {
        let doc = Sem.doc(Sem.block("abc"), Sem.block("def"))
        let blocks = BlockScanner.blocks(of: doc, intersecting: TextSelection(location: 99, length: 5))
        #expect(blocks.map(\.range) == [4 ..< 7])
    }

    /// The first frame of every editor: an empty document is one empty
    /// `.paragraph` block, and a caret (or any selection) into it must find
    /// exactly that block rather than an empty result.
    @Test func intersectingAnEmptyDocumentFindsTheSingleEmptyParagraphBlock() {
        let doc = AttributedString("")
        let caretBlocks = BlockScanner.blocks(of: doc, intersecting: .caret(at: 0))
        #expect(caretBlocks.count == 1)
        #expect(caretBlocks[0].range == 0 ..< 0)
        #expect(caretBlocks[0].isEmpty)
        #expect(caretBlocks[0].style == .paragraph)

        let selectionBlocks = BlockScanner.blocks(of: doc, intersecting: TextSelection(location: 0, length: 0))
        #expect(selectionBlocks == caretBlocks)
    }
}
