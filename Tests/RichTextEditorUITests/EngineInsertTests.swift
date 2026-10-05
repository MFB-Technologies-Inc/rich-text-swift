// EngineInsertTests.swift
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

    /// `UIKitEditorEngine.insert(_:)`, the engine side of a rich paste.
    /// The splice rule itself is `EngineCoreInsertTests`; these
    /// cover what the adapter adds: themed storage, undo, and reporting the
    /// edit to the delegate.
    @MainActor
    struct EngineInsertTests {
        private final class ChangeSpy: NSObject, UITextViewDelegate {
            var changes = 0
            func textViewDidChange(_: UITextView) {
                changes += 1
            }
        }

        private func editor(_ html: String) -> (UITextView, UIKitEditorEngine, UIWindow) {
            let textView = UITextView(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
            let window = UIWindow(frame: textView.frame)
            window.addSubview(textView)
            window.makeKeyAndVisible()
            let engine = UIKitEditorEngine(textView: textView)
            engine.text = RichTextHTML.decode(html)
            return (textView, engine, window)
        }

        private func step(_ textView: UITextView, _ action: () -> Void) {
            textView.undoManager?.beginUndoGrouping()
            action()
            textView.undoManager?.endUndoGrouping()
        }

        @Test func insertingAFragmentSplicesItIntoTheDocument() {
            let (textView, engine, window) = editor("<p>abcd</p>")
            engine.selection = .caret(at: 2)
            engine.insert(RichTextHTML.decode("<p><b>XY</b></p>"))

            #expect(RichTextHTML.encode(engine.text) == "<p>ab<b>XY</b>cd</p>")
            #expect(textView.textStorage.string == "abXYcd")
            #expect(textView.selectedRange == NSRange(location: 4, length: 0))
            _ = window
        }

        @Test func theInsertedTextIsDrawnInTheThemeNotItsSourceStyling() {
            let (textView, engine, window) = editor("<p>abcd</p>")
            engine.selection = .caret(at: 2)
            engine.insert(RichTextHTML.decode("<p><b>XY</b></p>"))

            let plain = textView.textStorage.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
            let pasted = textView.textStorage.attribute(.font, at: 2, effectiveRange: nil) as? UIFont
            #expect(pasted?.fontDescriptor.symbolicTraits.contains(.traitBold) == true)
            #expect(pasted?.pointSize == plain?.pointSize)
            _ = window
        }

        @Test func insertingAFragmentWithCRLFSplitsBlocks() {
            let engine = UIKitEditorEngine(textView: UITextView())
            engine.text = AttributedString("x")
            engine.selection = .caret(at: 1)

            engine.insert(AttributedString("\r\none\rtwo"))

            #expect(String(engine.text.characters) == "x\none\ntwo")
            #expect(engine.selection == .caret(at: 9))
        }

        @Test func insertingIsOneUndoStep() {
            let (textView, engine, window) = editor("<p>abcd</p>")
            // Explicit groups stand in for the one-group-per-event UIKit gets
            // from the run loop, which a synchronous test never turns.
            textView.undoManager?.groupsByEvent = false
            let before = engine.text
            step(textView) {
                engine.selection = .caret(at: 2)
                engine.insert(RichTextHTML.decode("<h1>A</h1><p>B</p>"))
            }
            #expect(engine.text != before)

            textView.undoManager?.undo()

            #expect(engine.text == before)
            #expect(textView.textStorage.string == "abcd")
            _ = window
        }

        @Test func insertingReportsTheChangeToTheDelegate() {
            let (textView, engine, window) = editor("<p>abcd</p>")
            let spy = ChangeSpy()
            textView.delegate = spy
            engine.selection = .caret(at: 2)
            engine.insert(RichTextHTML.decode("<p>XY</p>"))

            #expect(spy.changes == 1)
            _ = window
        }

        @Test func anEmptyFragmentReportsNothingAndRecordsNoUndo() {
            let (textView, engine, window) = editor("<p>abcd</p>")
            let spy = ChangeSpy()
            textView.delegate = spy
            engine.selection = .caret(at: 2)
            engine.insert(AttributedString(""))

            #expect(spy.changes == 0)
            #expect(textView.undoManager?.canUndo == false)
            _ = window
        }
    }
#endif
