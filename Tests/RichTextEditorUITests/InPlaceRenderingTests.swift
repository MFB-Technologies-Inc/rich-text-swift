// InPlaceRenderingTests.swift
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

    /// The in-place rendering path. Simulator-only: `swift test`
    /// on macOS never compiles the adapter.
    @MainActor
    struct InPlaceRenderingTests {
        private func editor(_ html: String) -> (UITextView, UIKitEditorEngine) {
            let textView = UITextView()
            let engine = UIKitEditorEngine(textView: textView)
            engine.text = RichTextHTML.decode(html)
            return (textView, engine)
        }

        @Test func aFormattingCommandKeepsTheSameTextStorageContents() {
            let (textView, engine) = editor("<p>hello</p>")
            let storageBefore = textView.textStorage
            engine.selection = TextSelection(location: 0, length: 5)
            engine.apply(.toggleBold)

            // Same storage object, same characters — only attributes moved.
            #expect(textView.textStorage === storageBefore)
            #expect(textView.textStorage.string == "hello")
            let font = textView.textStorage.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
            #expect(font?.fontDescriptor.symbolicTraits.contains(.traitBold) == true)
        }

        @Test func aFormattingCommandDoesNotClearAnExistingUndoStack() {
            // NOT proof of the in-place path's undo-coalescing rationale: measured identical
            // (`canUndo == true` both before and after) under the old
            // whole-`attributedText`-reassignment implementation too, because
            // `textView.attributedText = …` bypasses `shouldChangeTextIn:` (the
            // choke point UIKit's undo registration uses) — reassignment neither
            // adds nor clears undo entries. This is a regression guard against
            // formatting wiping out prior typing's undo history, not evidence
            // that in-place rendering changed undo behavior.
            let textView = UITextView()
            // A windowless text view's `undoManager` doesn't reflect real
            // responder-chain/undo-coalescing behavior. Attach it to a live
            // window so this assertion means what it claims to mean.
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
            window.addSubview(textView)
            window.makeKeyAndVisible()
            let engine = UIKitEditorEngine(textView: textView)
            textView.insertText("hello")
            engine.synchronizeFromTextView()
            #expect(textView.undoManager?.canUndo == true)

            engine.selection = TextSelection(location: 0, length: 5)
            engine.apply(.toggleBold)
            #expect(textView.undoManager?.canUndo == true)
        }

        @Test func aFormattingCommandLeavesIMEMarkedTextComposing() {
            // This is the assertion that actually discriminates the two
            // rendering paths (measured): under the old whole-`attributedText`
            // reassignment, `apply(.toggleBold)` below destroys the in-progress
            // IME composition (`markedTextRange` becomes nil); under the new
            // in-place attribute rewrite it survives. Text view must be in a key
            // window and first responder for marked text to work.
            let textView = UITextView()
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
            window.addSubview(textView)
            window.makeKeyAndVisible()
            textView.becomeFirstResponder()
            let engine = UIKitEditorEngine(textView: textView)

            textView.insertText("hi")
            engine.synchronizeFromTextView()
            textView.setMarkedText("あ", selectedRange: NSRange(location: 0, length: 1))
            // Load-bearing: `setMarkedText` mutates `textStorage` directly,
            // bypassing this engine's `text` setter, so `semanticText` is stale
            // until re-synced. Without this call the engine's stored string
            // still lacks the marked text, `render`'s string comparison sees a
            // difference, and even the new code takes the full-replacement
            // branch — which would destroy the composition regardless of which
            // implementation is under test, defeating the point of this probe.
            engine.synchronizeFromTextView()
            #expect(textView.markedTextRange != nil)

            engine.apply(.toggleBold)
            #expect(textView.markedTextRange != nil)
        }

        @Test func aGenuineDocumentChangeStillReplacesTheText() {
            let (textView, engine) = editor("<p>hello</p>")
            engine.text = RichTextHTML.decode("<h1>different</h1>")
            #expect(textView.textStorage.string == "different")
            let font = textView.textStorage.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
            #expect(font.map { Double($0.pointSize) } == Theme.default.heading1.fontSize)
        }

        @Test func aBlockCommandUpdatesRenderingWithoutChangingCharacters() {
            let (textView, engine) = editor("<p>hello</p>")
            engine.selection = .caret(at: 1)
            engine.apply(.toggleHeading(1))
            #expect(textView.textStorage.string == "hello")
            let font = textView.textStorage.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
            #expect(font.map { Double($0.pointSize) } == Theme.default.heading1.fontSize)
        }

        @Test func theSelectionSurvivesAnInPlaceRender() {
            let (textView, engine) = editor("<p>hello</p>")
            engine.selection = TextSelection(location: 1, length: 3)
            engine.apply(.toggleItalic)
            #expect(textView.selectedRange == NSRange(location: 1, length: 3))
        }
    }
#endif
