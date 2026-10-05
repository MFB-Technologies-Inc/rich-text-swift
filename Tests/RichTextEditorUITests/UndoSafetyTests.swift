// UndoSafetyTests.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
import RichTextCore
import Testing

#if os(iOS)
    @testable import RichTextEditorUI
    @testable import RichTextEngine
    import UIKit

    /// Engine-driven edits never pass through `shouldChangeTextIn:`, the choke
    /// point `UITextView` uses to register undo, so the engine registers its own
    /// entries (see `EngineUndoTests`). The one edit that registers nothing is a
    /// wholesale replacement through `text`: after it, the existing entries
    /// describe ranges in a document that no longer exists, and replaying one
    /// can restore inconsistent text or throw an uncatchable `NSRangeException`.
    /// This pins that such a replacement drops the stale history, and that no
    /// sequence of engine edits and undo leaves storage and document disagreeing.
    @MainActor
    struct UndoSafetyTests {
        private func editor(_ html: String) -> (UITextView, UIKitEditorEngine, UIWindow) {
            let textView = UITextView(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
            let window = UIWindow(frame: textView.frame)
            window.addSubview(textView)
            window.makeKeyAndVisible()
            let engine = UIKitEditorEngine(textView: textView)
            engine.text = RichTextHTML.decode(html)
            return (textView, engine, window)
        }

        /// Types the way a user does, so UIKit registers real undo entries.
        private func typeSomething(_ textView: UITextView, _ engine: UIKitEditorEngine) {
            textView.selectedRange = NSRange(location: textView.textStorage.length, length: 0)
            textView.insertText(" typed")
            engine.synchronizeFromTextView()
        }

        private func waitForUndoHistoryToClear(_ undoManager: UndoManager?) async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(2))
            while undoManager?.canUndo == true, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        @Test func aFormattingCommandKeepsTheUndoStack() {
            let (textView, engine, window) = editor("<p>hello</p>")
            typeSomething(textView, engine)
            #expect(textView.undoManager?.canUndo == true)

            engine.selection = TextSelection(location: 0, length: 5)
            engine.apply(.toggleBold)

            // Characters are untouched, so every registered range is still valid.
            #expect(textView.undoManager?.canUndo == true)
            _ = window
        }

        @Test func replacingTheDocumentDropsTheUndoStack() async throws {
            let (textView, engine, window) = editor("<p>hello</p>")
            typeSomething(textView, engine)
            #expect(textView.undoManager?.canUndo == true)

            engine.text = RichTextHTML.decode("<h1>something else entirely</h1>")

            // The preceding UIKit insertion can leave its undo group open
            // until this event ends. Clearing is deferred until then.
            try await waitForUndoHistoryToClear(textView.undoManager)
            #expect(textView.undoManager?.canUndo == false)
            _ = window
        }

        @Test func normalizingAUIKitCRLFPasteDropsEarlierUndoEntries() async throws {
            let (textView, engine, window) = editor("<p>hello</p>")
            typeSomething(textView, engine)
            #expect(textView.undoManager?.canUndo == true)

            textView.insertText("\r\nnext")
            engine.synchronizeFromTextView()

            #expect(textView.textStorage.string == "hello typed\nnext")
            try await waitForUndoHistoryToClear(textView.undoManager)
            #expect(textView.undoManager?.canUndo == false)
            _ = window
        }

        @Test func normalizingWhileAnUndoGroupIsOpenWaitsForItsClose() throws {
            let (textView, engine, window) = editor("<p>hello</p>")
            let undoManager = try #require(textView.undoManager)
            undoManager.groupsByEvent = false
            undoManager.beginUndoGrouping()
            textView.selectedRange = NSRange(location: textView.textStorage.length, length: 0)
            textView.insertText("\r\nnext")
            engine.synchronizeFromTextView()

            #expect(textView.textStorage.string == "hello\nnext")
            #expect(undoManager.groupingLevel > 0)
            undoManager.endUndoGrouping()
            #expect(undoManager.canUndo == false)
            _ = window
        }

        @Test func undoingAfterAnEngineEditDoesNotCorruptTheDocument() {
            // The scenario the guard exists for: type, Return, then undo. Whatever
            // undo does, the document and the storage must still agree.
            let (textView, engine, window) = editor("<ol><li>one</li></ol>")
            typeSomething(textView, engine)
            engine.selection = .caret(at: textView.textStorage.length)
            engine.insertNewline()

            textView.undoManager?.undo()
            engine.synchronizeFromTextView()

            #expect(textView.textStorage.string == String(engine.text.characters))
            _ = window
        }
    }
#endif
