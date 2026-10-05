// VocabularyTests.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
import RichTextCore
@testable import RichTextEngine
import Testing

struct VocabularyTests {
    @Test func selectionBounds() {
        let sel = TextSelection(location: 3, length: 4)
        #expect(sel.lowerBound == 3)
        #expect(sel.upperBound == 7)
        #expect(sel.isCollapsed == false)
        #expect(TextSelection.caret(at: 5).isCollapsed)
        #expect(TextSelection.caret(at: 5).upperBound == 5)
    }

    @Test func selectionClampsNegativeInputs() {
        let sel = TextSelection(location: -4, length: -9)
        #expect(sel.location == 0)
        #expect(sel.length == 0)
    }

    @Test func typingAttributesDefaultToOff() {
        let attrs = TypingAttributes()
        for flag in InlineFlag.allCases {
            #expect(attrs[flag] == false)
        }
        #expect(attrs.textColor == nil)
        #expect(attrs.blockStyle == nil)
    }

    @Test func typingAttributesSubscriptWrites() {
        var attrs = TypingAttributes()
        attrs[.italic] = true
        #expect(attrs.italic)
        #expect(attrs[.italic])
        #expect(attrs[.bold] == false)
    }

    @Test func formatStateSubscriptReadsEachFlag() {
        let state = FormatState(
            bold: .on, italic: .off, underline: .mixed, strikethrough: .on,
            textColor: RichTextColor(red: 1, green: 2, blue: 3),
            isTextColorMixed: false,
            blockStyle: .heading(2)
        )
        #expect(state[.bold] == .on)
        #expect(state[.italic] == .off)
        #expect(state[.underline] == .mixed)
        #expect(state[.strikethrough] == .on)
        #expect(state.blockStyle == .heading(2))
    }

    @Test func commandsAreEquatable() {
        #expect(FormatCommand.toggleBold == FormatCommand.toggleBold)
        #expect(FormatCommand.toggleHeading(1) != FormatCommand.toggleHeading(2))
        #expect(FormatCommand.toggleList(.ordered) != FormatCommand.toggleList(.unordered))
        // Black is normalized to "no color" at the command layer (EngineCore),
        // so these two commands have an identical effect once applied — but
        // they remain distinct *values* here, since this is testing
        // `FormatCommand` equality, not what EngineCore does with them.
        #expect(FormatCommand.setTextColor(nil) != FormatCommand.setTextColor(RichTextColor(red: 0, green: 0, blue: 0)))
        #expect(FormatCommand.setBlockStyle(.paragraph) == FormatCommand.setBlockStyle(.paragraph))
    }

    @Test func fixturesBuildFlatDocuments() {
        let doc = Sem.doc(Sem.block("Title", .heading(1)), Sem.block("Body"))
        #expect(String(doc.characters) == "Title\nBody")
        #expect(doc.runs.count == 2)
    }
}
