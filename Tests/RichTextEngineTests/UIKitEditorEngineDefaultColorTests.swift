// UIKitEditorEngineDefaultColorTests.swift
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

    /// Blocker 1's fourth ingest path: `RichTextEditor(text:)` is public, so a
    /// consumer can bind a document that already contains an explicit black run
    /// — built entirely outside the command layer (`EngineCore+Inline.swift`)
    /// and the HTML decoder, which are the only two places that normalized black
    /// before this fix. `UIKitEditorEngine.text`'s setter is the seam that
    /// document arrives through, and it must normalize too.
    @MainActor
    struct UIKitEditorEngineDefaultColorTests {
        private func blackDocument() -> AttributedString {
            var doc = AttributedString("hi")
            doc.blockStyle = .paragraph
            doc.textColor = RichTextColor.black
            return doc
        }

        @Test func settingADocumentContainingBlackThroughTheTextSetterComesBackWithNoColor() {
            let engine = UIKitEditorEngine(textView: UITextView())

            engine.text = blackDocument()

            #expect(engine.text.runs.first?.textColor == nil)
        }

        @Test func settingADocumentWithCRLFAndLoneCRCreatesSeparateBlocks() {
            let engine = UIKitEditorEngine(textView: UITextView())
            var document = AttributedString("first\r\nsecond\rthird")
            document.blockStyle = .heading(1)

            engine.text = document

            #expect(String(engine.text.characters) == "first\nsecond\nthird")
            #expect(BlockScanner.blocks(of: engine.text).map(\.style) == [.heading(1), .heading(1), .heading(1)])
        }

        @Test func aPrepopulatedTextViewIsNormalizedWithTheCaretMapped() {
            let textView = UITextView()
            textView.attributedText = NSAttributedString(string: "a\r\nb")
            textView.selectedRange = NSRange(location: 3, length: 0)

            let engine = UIKitEditorEngine(textView: textView)

            #expect(String(engine.text.characters) == "a\nb")
            #expect(textView.textStorage.string == "a\nb")
            #expect(engine.selection == .caret(at: 2))
        }

        @Test func aPrepopulatedTextViewKeepsASelectedRangeSpanningACRLF() {
            let textView = UITextView()
            textView.attributedText = NSAttributedString(string: "ab\r\ncd")
            textView.selectedRange = NSRange(location: 1, length: 4)

            let engine = UIKitEditorEngine(textView: textView)

            #expect(textView.textStorage.string == "ab\ncd")
            #expect(engine.selection == TextSelection(location: 1, length: 3))
            #expect(textView.selectedRange == NSRange(location: 1, length: 3))
        }

        @Test func assigningACRLFDocumentKeepsTheCaretOnTheSameCharacter() {
            let textView = UITextView()
            textView.attributedText = NSAttributedString(string: "a\r\nb\r\nc")
            textView.selectedRange = NSRange(location: 6, length: 0)
            let engine = UIKitEditorEngine(textView: textView)
            #expect(engine.selection == .caret(at: 4))

            // A consumer round-trip that changes formatting and reintroduces
            // CRLF: the caret indexes the normalized document, so it must not
            // be remapped through the incoming CRLFs.
            var incoming = AttributedString("a\r\nb\r\nc")
            incoming.bold = true
            engine.text = incoming

            #expect(String(engine.text.characters) == "a\nb\nc")
            #expect(engine.selection == .caret(at: 4))
        }

        @Test func crlfInsertedByUIKitIsNormalizedInStorageAndDocument() {
            let textView = UITextView()
            let engine = UIKitEditorEngine(textView: textView)
            engine.text = AttributedString("start")
            textView.selectedRange = NSRange(location: 5, length: 0)

            // What drag and drop or the `.system` paste fallback does: UIKit
            // edits storage without going through the engine.
            textView.insertText("\r\nnext")
            engine.synchronizeFromTextView()

            #expect(String(engine.text.characters) == "start\nnext")
            #expect(textView.textStorage.string == "start\nnext")
            #expect(engine.selection == .caret(at: 10))
            #expect(BlockScanner.blocks(of: engine.text).count == 2)
        }

        @Test func synchronizingASelectedRangeAcrossCRLFKeepsTheMappedRange() {
            let textView = UITextView()
            let engine = UIKitEditorEngine(textView: textView)
            textView.attributedText = NSAttributedString(string: "ab\r\ncd")
            textView.selectedRange = NSRange(location: 1, length: 4)

            engine.synchronizeFromTextView()

            #expect(textView.textStorage.string == "ab\ncd")
            #expect(engine.selection == TextSelection(location: 1, length: 3))
        }

        @Test func insertingCRBeforeAnExistingLFKeepsBothLineBreaks() {
            let textView = UITextView()
            let engine = UIKitEditorEngine(textView: textView)
            engine.text = AttributedString("first\nsecond")

            textView.textStorage.replaceCharacters(in: NSRange(location: 5, length: 0), with: "\r")
            textView.selectedRange = NSRange(location: 6, length: 0)
            engine.synchronizeFromTextView()

            #expect(String(engine.text.characters) == "first\n\nsecond")
            #expect(textView.textStorage.string == "first\n\nsecond")
            #expect(engine.selection == .caret(at: 6))
        }

        @Test func insertingLFCRBeforeAnExistingLFKeepsThreeLineBreaks() {
            let textView = UITextView()
            let engine = UIKitEditorEngine(textView: textView)
            engine.text = AttributedString("a\nb")

            textView.textStorage.replaceCharacters(in: NSRange(location: 1, length: 0), with: "\n\r")
            textView.selectedRange = NSRange(location: 3, length: 0)
            engine.synchronizeFromTextView()

            #expect(String(engine.text.characters) == "a\n\n\nb")
            #expect(textView.textStorage.string == "a\n\n\nb")
        }

        @Test func insertingCRLFAfterAnExistingLFKeepsTwoLineBreaks() {
            let textView = UITextView()
            let engine = UIKitEditorEngine(textView: textView)
            engine.text = AttributedString("a\nb")

            textView.textStorage.replaceCharacters(in: NSRange(location: 2, length: 0), with: "\r\n")
            textView.selectedRange = NSRange(location: 4, length: 0)
            engine.synchronizeFromTextView()

            #expect(String(engine.text.characters) == "a\n\nb")
            #expect(textView.textStorage.string == "a\n\nb")
        }
    }
#endif
