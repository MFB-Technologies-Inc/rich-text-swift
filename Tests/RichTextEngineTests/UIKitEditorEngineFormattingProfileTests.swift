// UIKitEditorEngineFormattingProfileTests.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
import RichTextCore
import Testing

#if canImport(UIKit)
    @testable import RichTextEngine
    import UIKit

    /// Every way formatting can reach a `UIKitEditorEngine` honors its
    /// `allowedFormatting`: the text binding, a rich paste, an edit UIKit
    /// makes to storage itself, commands, and a profile changed on a live
    /// editor. Simulator-only.
    @MainActor
    struct UIKitEditorEngineFormattingProfileTests {
        private func markdownEngine(_ textView: UITextView = UITextView()) -> UIKitEditorEngine {
            let engine = UIKitEditorEngine(textView: textView)
            engine.allowedFormatting = .markdown
            return engine
        }

        /// "b" bold and "u" underlined, in one paragraph.
        private func mixedDocument() -> AttributedString {
            var bold = AttributedString("b")
            bold.bold = true
            var underlined = AttributedString("u")
            underlined.underline = true
            var doc = bold + underlined
            doc.blockStyle = .paragraph
            return doc
        }

        private func hasUnderline(_ text: AttributedString) -> Bool {
            text.runs.contains { $0.underline == true }
        }

        @Test func theTextBindingDropsDisallowedFormattingAndKeepsTheRest() {
            let engine = markdownEngine()

            engine.text = mixedDocument()

            #expect(String(engine.text.characters) == "bu")
            #expect(!hasUnderline(engine.text))
            #expect(engine.text.runs.first?.bold == true)
        }

        @Test func aRichPasteDropsDisallowedFormatting() {
            let engine = markdownEngine()

            engine.insert(mixedDocument())

            #expect(String(engine.text.characters) == "bu")
            #expect(!hasUnderline(engine.text))
        }

        @Test func anEditUIKitMakesToStorageDropsDisallowedFormatting() throws {
            let textView = UITextView()
            let engine = markdownEngine(textView)

            // What UIKit's own paste or drag and drop leaves in storage.
            let pasted = try NSAttributedString(mixedDocument(), including: \.richText)
            textView.textStorage.insert(pasted, at: 0)
            engine.synchronizeFromTextView()

            #expect(String(engine.text.characters) == "bu")
            #expect(!hasUnderline(engine.text))
        }

        @Test func aDisallowedCommandDoesNothing() {
            let engine = markdownEngine()
            engine.text = AttributedString("x")
            engine.selection = TextSelection(location: 0, length: 1)

            engine.apply(.toggleUnderline)
            engine.apply(.setTextColor(RichTextColor(red: 255, green: 0, blue: 0)))
            engine.apply(.toggleBold)

            #expect(!hasUnderline(engine.text))
            #expect(engine.text.runs.first?.textColor == nil)
            #expect(engine.text.runs.first?.bold == true)
        }

        @Test func aDisallowedCommandAtTheCaretLeavesTypingAttributesAlone() {
            let engine = markdownEngine()

            engine.apply(.toggleUnderline)

            #expect(engine.typingAttributes.underline == false)
        }

        @Test func narrowingTheProfileStripsTheLiveDocumentAndTypingAttributes() {
            let engine = UIKitEditorEngine(textView: UITextView())
            engine.text = mixedDocument()
            engine.selection = .caret(at: 0)
            engine.apply(.toggleUnderline)
            #expect(engine.typingAttributes.underline)

            engine.allowedFormatting = .markdown

            #expect(String(engine.text.characters) == "bu")
            #expect(!hasUnderline(engine.text))
            #expect(engine.typingAttributes.underline == false)
        }

        @Test func headingsBecomeParagraphsWhenDisallowed() {
            let engine = UIKitEditorEngine(textView: UITextView())
            engine.allowedFormatting = RichTextFormatting.all.subtracting(.headings)
            var heading = AttributedString("Title")
            heading.blockStyle = .heading(1)

            engine.text = heading

            #expect(BlockScanner.blocks(of: engine.text).map(\.style) == [.paragraph])
        }
    }
#endif
