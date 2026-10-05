// ListMarkersTests.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
import RichTextCore
@testable import RichTextEngine
import Testing

struct ListMarkersTests {
    private func markers(_ text: AttributedString) -> [String?] {
        ListMarkers.markers(for: BlockScanner.blocks(of: text))
    }

    @Test func nonListBlocksHaveNoMarker() {
        let doc = Sem.doc(Sem.block("Title", .heading(1)), Sem.block("body"))
        #expect(markers(doc) == [nil, nil])
    }

    @Test func unorderedItemsUseABullet() {
        let doc = Sem.doc(
            Sem.block("a", .listItem(.unordered, depth: 0)),
            Sem.block("b", .listItem(.unordered, depth: 0))
        )
        #expect(markers(doc) == ["•", "•"])
    }

    @Test func orderedItemsNumberSequentially() {
        let doc = Sem.doc(
            Sem.block("a", .listItem(.ordered, depth: 0)),
            Sem.block("b", .listItem(.ordered, depth: 0)),
            Sem.block("c", .listItem(.ordered, depth: 0))
        )
        #expect(markers(doc) == ["1.", "2.", "3."])
    }

    @Test func aParagraphBetweenListsRestartsNumbering() {
        let doc = Sem.doc(
            Sem.block("a", .listItem(.ordered, depth: 0)),
            Sem.block("interruption"),
            Sem.block("b", .listItem(.ordered, depth: 0))
        )
        #expect(markers(doc) == ["1.", nil, "1."])
    }

    @Test func switchingKindAtTheSameDepthRestartsNumbering() {
        let doc = Sem.doc(
            Sem.block("a", .listItem(.ordered, depth: 0)),
            Sem.block("b", .listItem(.unordered, depth: 0)),
            Sem.block("c", .listItem(.ordered, depth: 0))
        )
        #expect(markers(doc) == ["1.", "•", "1."])
    }

    @Test func nestingDoesNotInterruptTheParentSequence() {
        let doc = Sem.doc(
            Sem.block("one", .listItem(.ordered, depth: 0)),
            Sem.block("nested", .listItem(.ordered, depth: 1)),
            Sem.block("two", .listItem(.ordered, depth: 0))
        )
        #expect(markers(doc) == ["1.", "1.", "2."])
    }

    @Test func aNestedSequenceRestartsEachTimeItIsReentered() {
        let doc = Sem.doc(
            Sem.block("one", .listItem(.ordered, depth: 0)),
            Sem.block("n1", .listItem(.ordered, depth: 1)),
            Sem.block("n2", .listItem(.ordered, depth: 1)),
            Sem.block("two", .listItem(.ordered, depth: 0)),
            Sem.block("n3", .listItem(.ordered, depth: 1))
        )
        #expect(markers(doc) == ["1.", "1.", "2.", "2.", "1."])
    }

    @Test func bulletGlyphVariesByDepthAndCycles() {
        #expect(ListMarkers.bullet(forDepth: 0) == "•")
        #expect(ListMarkers.bullet(forDepth: 1) == "◦")
        #expect(ListMarkers.bullet(forDepth: 2) == "▪")
        #expect(ListMarkers.bullet(forDepth: 3) == "•")
    }

    @Test func nestedBulletsUseTheirDepthGlyph() {
        let doc = Sem.doc(
            Sem.block("a", .listItem(.unordered, depth: 0)),
            Sem.block("b", .listItem(.unordered, depth: 1))
        )
        #expect(markers(doc) == ["•", "◦"])
    }

    @Test func emptyDocumentHasOneMarkerlessBlock() {
        #expect(markers(AttributedString()) == [nil])
    }

    @Test func anEmptyBlockBetweenItemsIsNumberedAsAnItem() {
        // An empty block can't carry a role, but one between two items of the
        // same list is an empty item of it (GitHub issue #74), so the run
        // counts through it rather than restarting.
        var doc = Sem.block("a", .listItem(.ordered, depth: 0))
        doc += AttributedString("\n\n")
        doc += Sem.block("b", .listItem(.ordered, depth: 0))
        #expect(markers(doc) == ["1.", "2.", "3."])
    }

    // MARK: - Over effective blocks (the pending-role rendering fix)

    /// The bug this milestone fixes: pressing Return at the end of "1." must
    /// show "2." on the new, still-empty line immediately — not only once a
    /// character exists to carry the role. `effectiveBlocks` substitutes the
    /// pending role onto the caret's empty block, and because `markers(for:)`
    /// just operates on whatever blocks it's handed, the pending item
    /// automatically takes part in the ordinal run.
    @Test func pendingOrderedItemShowsTheNextNumberImmediately() {
        var doc = Sem.block("one", .listItem(.ordered, depth: 0))
        doc += AttributedString("\n")
        let blocks = BlockScanner.effectiveBlocks(
            of: doc,
            selection: .caret(at: 4),
            pendingBlockStyle: .listItem(.ordered, depth: 0)
        )
        #expect(ListMarkers.markers(for: blocks) == ["1.", "2."])
    }

    @Test func pendingUnorderedItemShowsTheDepthAppropriateBullet() {
        var doc = Sem.block("one", .listItem(.unordered, depth: 1))
        doc += AttributedString("\n")
        let blocks = BlockScanner.effectiveBlocks(
            of: doc,
            selection: .caret(at: 4),
            pendingBlockStyle: .listItem(.unordered, depth: 1)
        )
        #expect(ListMarkers.markers(for: blocks) == ["◦", "◦"])
    }

    @Test func pendingItemAtDepthTwoNumbersWithinItsOwnLevel() {
        var doc = Sem.doc(
            Sem.block("parent", .listItem(.ordered, depth: 0)),
            Sem.block("child", .listItem(.ordered, depth: 1))
        )
        doc += AttributedString("\n")
        let blocks = BlockScanner.effectiveBlocks(
            of: doc,
            selection: .caret(at: TextOffsets.length(of: doc)),
            pendingBlockStyle: .listItem(.ordered, depth: 1)
        )
        #expect(ListMarkers.markers(for: blocks) == ["1.", "1.", "2."])
    }

    // MARK: - markers(forLineStartOffsets:blocks:) — one marker per block-starting line

    //
    // TextKit does not always give one layout fragment per block: the
    // document-final empty block is laid out as a second `NSTextLineFragment`
    // inside the *same* fragment as the preceding item, rather than getting a
    // fragment of its own. `ListMarkerFragment` therefore cannot assume "one
    // fragment = one marker" — it must draw a marker on every *line* that
    // begins a block. This pure function is the decision: a line gets a
    // marker exactly when its start offset equals the start of a block that
    // has one.

    @Test func aSingleLineItemGetsItsMarkerOnLineZero() {
        let blocks = [DocumentBlock(location: 0, length: 3, style: .listItem(.ordered, depth: 0))]
        #expect(ListMarkers.markers(forLineStartOffsets: [0], blocks: blocks) == [0: "1."])
    }

    @Test func aWrappedItemsMarkerStaysOnlyOnItsFirstLine() {
        // One block spanning two visual lines (a wrapped item). Only the
        // first line's start (0) is the block's own start; the wrapped
        // continuation's start (5) falls mid-block and matches nothing —
        // this is the M4 regression (bullet drawn on line 2) to protect.
        let blocks = [DocumentBlock(location: 0, length: 20, style: .listItem(.unordered, depth: 0))]
        #expect(ListMarkers.markers(forLineStartOffsets: [0, 5], blocks: blocks) == [0: "•"])
    }

    @Test func aFragmentsSecondLineBeginningTheTrailingEmptyBlockGetsItsOwnMarker() {
        // The trailing case this milestone fixes: one fragment holding two
        // lines because TextKit didn't give the document-final empty block
        // a fragment of its own. The second line's start (10) equals that
        // empty block's own start, so it gets its own marker too.
        let blocks = [
            DocumentBlock(location: 0, length: 9, style: .listItem(.ordered, depth: 0)),
            DocumentBlock(location: 10, length: 0, style: .listItem(.ordered, depth: 0)),
        ]
        #expect(ListMarkers.markers(forLineStartOffsets: [0, 10], blocks: blocks) == [0: "1.", 1: "2."])
    }

    @Test func aParagraphFragmentHasNoMarkers() {
        let blocks = [DocumentBlock(location: 0, length: 6, style: .paragraph)]
        #expect(ListMarkers.markers(forLineStartOffsets: [0], blocks: blocks).isEmpty)
    }

    @Test func anEmptyBlocksOnlyDocumentHasNoMarkers() {
        let blocks = [DocumentBlock(location: 0, length: 0, style: .paragraph)]
        #expect(ListMarkers.markers(forLineStartOffsets: [0], blocks: blocks).isEmpty)
    }
}
