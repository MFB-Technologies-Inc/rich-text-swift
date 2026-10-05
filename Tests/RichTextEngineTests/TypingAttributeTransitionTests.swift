// TypingAttributeTransitionTests.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
import RichTextCore
@testable import RichTextEngine
import Testing

/// New suite (rather than folding into `FormatStateTests`) because this is
/// exercising a different concern: not "what does the document say the state
/// is right now" but "how does typing-attribute state transition across a
/// selection change" — the pending-block-style leak fix (fix wave A, Part 1).
struct TypingAttributeTransitionTests {
    private func moved(
        to selection: TextSelection,
        in text: AttributedString,
        previous: TypingAttributes,
        previouslyAt previousSelection: TextSelection
    ) -> TypingAttributes {
        EngineCore.typingAttributes(
            movingTo: selection,
            in: text,
            previous: previous,
            previouslyAt: previousSelection
        )
    }

    @Test func caretReassignedToTheSameEmptyBlockPreservesThePendingStyle() {
        // "abc\n\ndef" — the middle block (offset 4) is empty.
        let doc = Sem.doc(Sem.block("abc"), Sem.block(""), Sem.block("def"))
        var previous = TypingAttributes()
        previous.blockStyle = .heading(1)
        let result = moved(
            to: .caret(at: 4),
            in: doc,
            previous: previous,
            previouslyAt: .caret(at: 4)
        )
        #expect(result.blockStyle == .heading(1))
    }

    @Test func caretMovingToADifferentEmptyBlockDropsThePendingStyle() {
        // Two distinct empty blocks: "\n\n\n" -> blocks at 0, 1, 2 all empty.
        let doc = Sem.doc(Sem.block(""), Sem.block(""), Sem.block(""))
        var previous = TypingAttributes()
        previous.blockStyle = .heading(1)
        // Previously in the first empty block (offset 0), now the third (offset 2).
        let result = moved(
            to: .caret(at: 2),
            in: doc,
            previous: previous,
            previouslyAt: .caret(at: 0)
        )
        // This is the leak the fix closes: must NOT still be .heading(1).
        #expect(result.blockStyle == nil)
    }

    @Test func caretMovingFromAnEmptyBlockToANonEmptyOneDropsThePendingStyle() {
        let doc = Sem.doc(Sem.block(""), Sem.block("abc"))
        var previous = TypingAttributes()
        previous.blockStyle = .heading(2)
        let result = moved(
            to: .caret(at: 2),
            in: doc,
            previous: previous,
            previouslyAt: .caret(at: 0)
        )
        #expect(result.blockStyle == nil)
    }

    @Test func nonCollapsedSelectionDropsThePendingStyle() {
        let doc = Sem.doc(Sem.block(""), Sem.block("abcdef"))
        var previous = TypingAttributes()
        previous.blockStyle = .heading(1)
        let result = moved(
            to: TextSelection(location: 1, length: 3),
            in: doc,
            previous: previous,
            previouslyAt: .caret(at: 0)
        )
        #expect(result.blockStyle == nil)
    }

    @Test func noPreviousPendingStyleYieldsNil() {
        let doc = Sem.doc(Sem.block(""), Sem.block(""))
        let previous = TypingAttributes()
        let result = moved(
            to: .caret(at: 0),
            in: doc,
            previous: previous,
            previouslyAt: .caret(at: 0)
        )
        #expect(result.blockStyle == nil)
    }

    @Test func inlineFlagsAndColorAreAlwaysReDerivedFromTheDocument() {
        // Previous typing attributes claim bold+red, but the caret lands on
        // plain text — the derived attributes must reflect the document, not
        // whatever `previous` happened to carry.
        let doc = Sem.block("abcdef")
        var previous = TypingAttributes()
        previous.bold = true
        previous.textColor = RichTextColor(red: 255, green: 0, blue: 0)
        let result = moved(
            to: .caret(at: 3),
            in: doc,
            previous: previous,
            previouslyAt: .caret(at: 0)
        )
        #expect(result.bold == false)
        #expect(result.textColor == nil)
    }
}
