// EmptyListItemBlockTests.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
import RichTextCore
@testable import RichTextEngine
import Testing

/// `BlockScanner` reports an empty block between two items of the same list
/// as an empty item of that list, the rule the encoder writes it by, so the
/// editor draws, numbers and types into it as an item.
struct EmptyListItemBlockTests {
    private let one = BlockStyle.listItem(.ordered, depth: 0)

    @Test func anEmptyBlockBetweenItemsIsAnItem() {
        let doc = Sem.doc(Sem.block("a", one), Sem.block(""), Sem.block("c", one))
        #expect(BlockScanner.blocks(of: doc).map(\.style) == [one, one, one])
    }

    @Test func anEmptyBlockAtTheEndOfAListIsAParagraph() {
        let doc = Sem.doc(Sem.block("a", one), Sem.block(""))
        #expect(BlockScanner.blocks(of: doc).map(\.style) == [one, .paragraph])
    }

    @Test func typingIntoTheEmptyItemMakesAListItem() {
        let doc = Sem.doc(Sem.block("a", one), Sem.block(""), Sem.block("c", one))
        let state = EngineCore.formatState(of: doc, selection: .caret(at: 2), typingAttributes: TypingAttributes())
        #expect(state.blockStyle == one)
    }
}
