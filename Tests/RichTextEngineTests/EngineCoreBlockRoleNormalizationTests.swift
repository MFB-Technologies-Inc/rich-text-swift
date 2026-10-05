// EngineCoreBlockRoleNormalizationTests.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
import RichTextCore
@testable import RichTextEngine
import Testing

/// Covers `EngineCore.fillingMissingBlockStyle(_:with:)`: text with no block
/// role gets one, so no document the engine holds carries a `nil` role on
/// its characters (GitHub issue #73). An empty block has no characters to
/// hold a role, so it stays as it is.
struct EngineCoreBlockRoleNormalizationTests {
    private func block(_ text: String, _ style: BlockStyle?) -> AttributedString {
        var block = AttributedString(text)
        block.blockStyle = style
        return block
    }

    @Test func textWithNoRoleGetsTheGivenRole() {
        let filled = EngineCore.fillingMissingBlockStyle(block("x", nil), with: .heading(1))
        #expect(filled.blockStyle == .heading(1))
    }

    @Test func textWithARoleKeepsIt() {
        let doc = block("x", .listItem(.ordered, depth: 1))
        #expect(EngineCore.fillingMissingBlockStyle(doc, with: .heading(1)) == doc)
    }

    @Test func aRolelessBlockDoesNotChangeTheBlockBeforeIt() {
        let doc = block("a", .blockquote) + AttributedString("\nb")
        let filled = EngineCore.fillingMissingBlockStyle(doc, with: .heading(2))
        #expect(BlockScanner.blocks(of: filled).map(\.style) == [.blockquote, .heading(2)])
    }

    @Test func anEmptyBlockStaysEmpty() {
        let doc = block("a", .paragraph) + AttributedString("\n\n") + block("b", .paragraph)
        let filled = EngineCore.fillingMissingBlockStyle(doc, with: .heading(1))
        #expect(String(filled.characters) == "a\n\nb")
        #expect(BlockScanner.blocks(of: filled).map(\.style) == [.paragraph, .paragraph, .paragraph])
    }

    @Test func firstRolelessOffsetSkipsTextWithARoleAndEmptyBlocks() {
        let doc = block("ab", .heading(1)) + AttributedString("\n\n") + block("cd", nil)
        #expect(EngineCore.firstRolelessOffset(in: doc) == 4)
        #expect(EngineCore.firstRolelessOffset(in: block("ab", .paragraph)) == nil)
    }

    /// A block that mixes text with a role and text without one takes the
    /// given role throughout, the way a block can only have one role.
    @Test func aBlockMixingRolesTakesTheGivenRole() {
        let doc = block("x", nil) + block("d", .paragraph)
        #expect(EngineCore.fillingMissingBlockStyle(doc, with: .heading(1)).blockStyle == .heading(1))
    }

    /// A consumer's document enters through `normalizedIngest`; its roleless
    /// text becomes a paragraph, which is what the encoder writes for it.
    @Test func ingestGivesRolelessTextTheParagraphRole() {
        let ingested = EngineCore.normalizedIngest(AttributedString("plain"), selection: .caret(at: 0))
        #expect(ingested?.text.blockStyle == .paragraph)
    }
}
