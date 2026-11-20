// EngineCoreFormattingProfileTests.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
import RichTextCore
@testable import RichTextEngine
import Testing

/// Covers the rules behind `RichTextFormatting`: what stripping a document
/// or typing attributes removes, and which commands a profile lets through.
struct EngineCoreFormattingProfileTests {
    private let red = RichTextColor(red: 255, green: 0, blue: 0)

    private func run(_ text: String, style: BlockStyle = .paragraph) -> AttributedString {
        var a = AttributedString(text)
        a.blockStyle = style
        return a
    }

    @Test func stripsDisallowedInlineFormattingAndKeepsTheText() {
        var doc = run("styled")
        doc.bold = true
        doc.underline = true
        doc.textColor = red

        let stripped = EngineCore.strippingDisallowed(doc, allowing: .markdown)

        #expect(String(stripped.characters) == "styled")
        #expect(stripped.runs.first?.bold == true)
        #expect(stripped.runs.first?.underline == nil)
        #expect(stripped.runs.first?.textColor == nil)
    }

    @Test func disallowedBlockRolesBecomeParagraphs() {
        let doc = run("h", style: .heading(1)) + AttributedString("\n") + run("l", style: .listItem(.ordered, depth: 1))
            + AttributedString("\n") + run("q", style: .blockquote)

        let stripped = EngineCore.strippingDisallowed(doc, allowing: [.bold])

        #expect(String(stripped.characters) == "h\nl\nq")
        for block in BlockScanner.blocks(of: stripped) {
            #expect(block.style == .paragraph)
        }
    }

    @Test func allowedFormattingIsLeftAlone() {
        var doc = run("h", style: .heading(2))
        doc.italic = true
        doc.underline = true
        doc.textColor = red

        #expect(EngineCore.strippingDisallowed(doc, allowing: .all) == doc)
    }

    @Test func stripsDisallowedTypingAttributes() {
        let typing = TypingAttributes(
            bold: true, underline: true, strikethrough: true, textColor: red, blockStyle: .heading(1)
        )

        let stripped = EngineCore.strippingDisallowed(typing, allowing: [.bold])

        #expect(stripped == TypingAttributes(bold: true, blockStyle: .paragraph))
    }

    @Test func ingestStripsDisallowedFormatting() {
        var doc = run("u")
        doc.underline = true

        let ingested = EngineCore.normalizedIngest(doc, selection: .caret(at: 0), allowing: .markdown)

        #expect(ingested?.text == run("u"))
    }

    @Test func ingestReportsNoChangeWhenNothingIsDisallowed() {
        var doc = run("b")
        doc.bold = true

        #expect(EngineCore.normalizedIngest(doc, selection: .caret(at: 0), allowing: .markdown) == nil)
    }

    @Test func commandsNeedTheirFormatting() {
        let cases: [(FormatCommand, RichTextFormatting)] = [
            (.toggleBold, .bold),
            (.toggleItalic, .italic),
            (.toggleUnderline, .underline),
            (.toggleStrikethrough, .strikethrough),
            (.setTextColor(red), .textColor),
            (.toggleHeading(1), .headings),
            (.toggleList(.unordered), .bulletedLists),
            (.toggleList(.ordered), .numberedLists),
            (.setBlockStyle(.blockquote), .blockquotes),
            (.setBlockStyle(.heading(2)), .headings),
        ]
        for (command, option) in cases {
            #expect(command.isAllowed(by: option))
            #expect(!command.isAllowed(by: RichTextFormatting.all.subtracting(option)))
        }
    }

    @Test func removingFormattingIsAlwaysAllowed() {
        let none = RichTextFormatting()
        #expect(FormatCommand.setTextColor(nil).isAllowed(by: none))
        #expect(FormatCommand.setTextColor(.black).isAllowed(by: none))
        #expect(FormatCommand.setBlockStyle(.paragraph).isAllowed(by: none))
    }
}
