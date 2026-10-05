// MixedSelectionTypingTests.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
import RichTextCore
import Testing

#if os(iOS)
    @testable import RichTextEngine
    import UIKit

    /// Text typed over a selection that spans blocks of different roles takes
    /// the role of the block where the selection starts, the rule a paste
    /// already follows. Before, it got no role at all.
    ///
    /// The keyboard deletes the selection before it inserts, and when that
    /// empties a block UIKit resets the typing attributes, so the typed text
    /// arrives with no semantic attributes at all. These tests reproduce that
    /// by putting bare text into storage, which is what the keyboard did in
    /// the Demo app.
    @MainActor
    struct MixedSelectionTypingTests {
        private func editor(_ html: String) -> (UITextView, UIKitEditorEngine, UIWindow) {
            let textView = UITextView(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
            let window = UIWindow(frame: textView.frame)
            window.addSubview(textView)
            window.makeKeyAndVisible()
            let engine = UIKitEditorEngine(textView: textView)
            engine.text = RichTextHTML.decode(html)
            return (textView, engine, window)
        }

        private func typeBare(
            _ text: String,
            over selection: TextSelection,
            _ textView: UITextView,
            _ engine: UIKitEditorEngine
        ) {
            engine.selection = selection
            let range = NSRange(location: selection.location, length: selection.length)
            textView.textStorage.replaceCharacters(in: range, with: NSAttributedString(string: text))
            textView.selectedRange = NSRange(location: selection.location + text.utf16.count, length: 0)
            // UIKit reports the selection change before the text change, so the
            // engine sees the post-edit caret first.
            engine.synchronizeSelection()
            engine.synchronizeFromTextView()
        }

        private func type(_ text: String, over selection: TextSelection, in html: String) -> AttributedString {
            let (textView, engine, window) = editor(html)
            typeBare(text, over: selection, textView, engine)
            _ = window
            return engine.text
        }

        @Test func selectAllOverAHeadingAndAListKeepsTheHeading() {
            let doc = type("x", over: TextSelection(location: 0, length: 3), in: "<h1>T</h1><ul><li>a</li></ul>")
            #expect(doc.blockStyle == .heading(1))
            #expect(RichTextHTML.encode(doc) == "<h1>x</h1>")
            #expect(RichTextHTML.decode(RichTextHTML.encode(doc)) == doc)
        }

        @Test func aSelectionFromAHeadingIntoAParagraphKeepsTheHeading() {
            let doc = type("x", over: TextSelection(location: 0, length: 4), in: "<h1>ab</h1><p>cd</p>")
            #expect(RichTextHTML.encode(doc) == "<h1>xd</h1>")
            #expect(RichTextHTML.decode(RichTextHTML.encode(doc)) == doc)
        }

        @Test func aSelectionFromAListItemKeepsItsKindAndDepth() {
            let doc = type(
                "x",
                over: TextSelection(location: 2, length: 4),
                in: "<ol><li>a<ol><li>bc</li></ol></li></ol><p>de</p>"
            )
            #expect(RichTextHTML.encode(doc) == "<ol><li>a<ol><li>xe</li></ol></li></ol>")
            #expect(RichTextHTML.decode(RichTextHTML.encode(doc)) == doc)
        }

        /// Dictation, a QuickType suggestion or autocorrect inserts several
        /// characters at once, so the caret after the edit can sit in a later
        /// block of the document as it was before.
        @Test func aMultiCharacterInsertionKeepsTheFirstBlocksRole() {
            let doc = type(
                "hello world",
                over: TextSelection(location: 0, length: 3),
                in: "<h1>H</h1><p>paragraph text</p>"
            )
            #expect(RichTextHTML.encode(doc) == "<h1>hello worldaragraph text</h1>")
        }

        @Test func theTypedTextIsDrawnInTheFirstBlocksStyle() {
            let (textView, engine, window) = editor("<h1>ab</h1><p>cd</p>")
            let heading = textView.textStorage.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
            typeBare("x", over: TextSelection(location: 0, length: 4), textView, engine)
            let typed = textView.textStorage.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
            #expect(typed == heading)
            _ = window
        }

        @Test func typingOverTheSelectionStaysOneUndoStep() {
            let (textView, engine, window) = editor("<h1>ab</h1><p>cd</p>")
            let before = engine.text
            textView.undoManager?.groupsByEvent = false
            textView.undoManager?.beginUndoGrouping()
            engine.selection = TextSelection(location: 0, length: 4)
            textView.insertText("x")
            engine.synchronizeFromTextView()
            textView.undoManager?.endUndoGrouping()
            #expect(RichTextHTML.encode(engine.text) == "<h1>xd</h1>")
            textView.undoManager?.undo()
            // The text view's delegate syncs the engine after an undo in the app.
            engine.synchronizeFromTextView()
            #expect(textView.textStorage.string == "ab\ncd")
            #expect(engine.text == before)
            _ = window
        }

        @Test func theToolbarStillShowsNoBlockRoleForTheMixedSelection() {
            let (_, engine, window) = editor("<h1>T</h1><ul><li>a</li></ul>")
            engine.selection = TextSelection(location: 0, length: 3)
            #expect(engine.formatState.blockStyle == nil)
            _ = window
        }
    }
#endif
