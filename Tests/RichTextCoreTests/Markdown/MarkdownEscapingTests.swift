// MarkdownEscapingTests.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
@testable import RichTextCore
import Testing

struct MarkdownEscapingTests {
    @Test(arguments: ["\\", "*", "_", "`", "~", "[", "]", "<", "&", "|"])
    func inlineSpecialCharactersAreBackslashEscaped(_ character: String) {
        #expect(MarkdownEscaping.escapeInline("a\(character)b") == "a\\\(character)b")
    }

    @Test func plainTextIsUnchanged() {
        #expect(MarkdownEscaping.escapeInline("Hello, world. #1 - ok > 2 = 2!") == "Hello, world. #1 - ok > 2 = 2!")
    }

    @Test(arguments: ["#", ">", "-", "+", "="])
    func blockMarkersAtLineStartAreEscaped(_ character: String) {
        #expect(MarkdownEscaping.escapeLineStart("\(character) x") == "\\\(character) x")
    }

    @Test func orderedListNumberAtLineStartIsEscaped() {
        #expect(MarkdownEscaping.escapeLineStart("1. x") == "1\\. x")
        #expect(MarkdownEscaping.escapeLineStart("2024) x") == "2024\\) x")
        #expect(MarkdownEscaping.escapeLineStart("2024 x") == "2024 x")
    }

    @Test func lineStartAlsoEscapesInline() {
        #expect(MarkdownEscaping.escapeLineStart("*a*") == "\\*a\\*")
    }

    @Test func headingEscapesEveryHash() {
        #expect(MarkdownEscaping.escapeHeading("C# #1 #") == "C\\# \\#1 \\#")
    }
}
