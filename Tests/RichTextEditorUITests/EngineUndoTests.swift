// EngineUndoTests.swift
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

    /// Engine-driven edits (formatting commands, Return) register their own
    /// undo entries on the text view's `undoManager`, interleaved with the
    /// entries UIKit registers for typing. Each entry restores the whole
    /// pre-edit document, so the stack stays consistent: undoing an engine
    /// entry puts back exactly the document UIKit's older entries describe.
    @MainActor
    struct EngineUndoTests {
        private func editor(
            _ html: String,
            groupsByEvent: Bool = false
        ) -> (UITextView, UIKitEditorEngine, UIWindow) {
            let textView = UITextView(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
            let window = UIWindow(frame: textView.frame)
            window.addSubview(textView)
            window.makeKeyAndVisible()
            let engine = UIKitEditorEngine(textView: textView)
            engine.text = RichTextHTML.decode(html)
            // Explicit groups stand in for the one-group-per-event UIKit gets
            // from the run loop, which a synchronous test never turns.
            textView.undoManager?.groupsByEvent = groupsByEvent
            return (textView, engine, window)
        }

        /// One user action, in its own undo group, the way a real event gets one.
        private func step(_ textView: UITextView, _ action: () -> Void) {
            textView.undoManager?.beginUndoGrouping()
            action()
            textView.undoManager?.endUndoGrouping()
        }

        /// Types the way a user does, so UIKit registers real undo entries.
        private func type(_ text: String, _ textView: UITextView, _ engine: UIKitEditorEngine) {
            step(textView) {
                textView.selectedRange = NSRange(location: textView.textStorage.length, length: 0)
                textView.insertText(text)
                engine.synchronizeFromTextView()
            }
        }

        /// Types one keystroke per run-loop pass at the current caret, never
        /// touching the selection, the way a keyboard does. Needs an editor
        /// with `groupsByEvent` on: UIKit's own grouping is what merges a run
        /// of keystrokes into one undo step, and explicit groups defeat it.
        private func keystrokes(_ text: String, _ textView: UITextView, _ engine: UIKitEditorEngine) {
            for character in text {
                textView.insertText(String(character))
                engine.synchronizeFromTextView()
                turnRunLoop()
            }
        }

        /// Lets the run loop close the undo group it opened for this event.
        private func turnRunLoop() {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
        }

        private func html(_ engine: UIKitEditorEngine) -> String {
            RichTextHTML.encode(engine.text)
        }

        @Test func boldIsUndoable() {
            let (textView, engine, window) = editor("<p>hello</p>")
            let before = engine.text
            step(textView) {
                engine.selection = TextSelection(location: 0, length: 5)
                engine.apply(.toggleBold)
            }
            #expect(engine.text != before)

            textView.undoManager?.undo()

            #expect(engine.text == before)
            #expect(textView.textStorage.string == String(engine.text.characters))
            _ = window
        }

        @Test func undoneBoldIsRedoable() {
            let (textView, engine, window) = editor("<p>hello</p>")
            step(textView) {
                engine.selection = TextSelection(location: 0, length: 5)
                engine.apply(.toggleBold)
            }
            let bolded = engine.text

            textView.undoManager?.undo()
            textView.undoManager?.redo()

            #expect(engine.text == bolded)
            _ = window
        }

        @Test func returnIsUndoable() {
            let (textView, engine, window) = editor("<ul><li>one</li></ul>")
            let before = engine.text
            step(textView) {
                engine.selection = .caret(at: textView.textStorage.length)
                engine.insertNewline()
            }
            #expect(engine.text != before)

            textView.undoManager?.undo()

            #expect(engine.text == before)
            #expect(textView.textStorage.string == "one")
            #expect(textView.selectedRange == NSRange(location: 3, length: 0))
            _ = window
        }

        @Test func returnKeepsEarlierTypingUndoable() {
            let (textView, engine, window) = editor("<ul><li>one</li></ul>")
            type(" two", textView, engine)
            step(textView) {
                engine.selection = .caret(at: textView.textStorage.length)
                engine.insertNewline()
            }

            textView.undoManager?.undo()
            #expect(textView.textStorage.string == "one two")
            textView.undoManager?.undo()
            engine.synchronizeFromTextView()

            #expect(textView.textStorage.string == "one")
            #expect(String(engine.text.characters) == "one")
            _ = window
        }

        /// An empty list item's role lives only in the pending typing
        /// attributes, so undoing the typing in it must bring the pending
        /// style back, not just the empty block (GitHub issue #21).
        @Test func undoingTheTypingInANewListItemKeepsItsBullet() {
            let (textView, engine, window) = editor("<ul><li>one</li></ul>")
            step(textView) {
                engine.selection = .caret(at: textView.textStorage.length)
                engine.insertNewline()
            }
            let afterReturn = engine.typingAttributes
            #expect(afterReturn.blockStyle == .listItem(.unordered, depth: 0))
            type("two", textView, engine)

            textView.undoManager?.undo()
            engine.synchronizeFromTextView()

            #expect(textView.textStorage.string == "one\n")
            #expect(engine.typingAttributes == afterReturn)
            #expect(engine.formatState.blockStyle == .listItem(.unordered, depth: 0))

            // The later undos are unaffected: the Return, then the typing.
            textView.undoManager?.undo()
            engine.synchronizeFromTextView()
            #expect(textView.textStorage.string == "one")
            #expect(engine.typingAttributes.blockStyle == nil)
            _ = window
        }

        /// Undoing a caret command at the empty item forgets only that
        /// command's state, not the one the Return left at the same caret.
        @Test func undoingAListToggleInANewItemStillKeepsTheBulletForLaterUndos() {
            let (textView, engine, window) = editor("<ul><li>one</li></ul>")
            step(textView) {
                engine.selection = .caret(at: textView.textStorage.length)
                engine.insertNewline()
            }
            let afterReturn = engine.typingAttributes
            step(textView) { engine.apply(.toggleList(.unordered)) }
            #expect(engine.typingAttributes.blockStyle == .paragraph)
            textView.undoManager?.undo()
            #expect(engine.typingAttributes == afterReturn)
            type("two", textView, engine)

            textView.undoManager?.undo()
            engine.synchronizeFromTextView()

            #expect(textView.textStorage.string == "one\n")
            #expect(engine.typingAttributes == afterReturn)
            _ = window
        }

        /// The interleaving the issue is about: typing, a command, more typing,
        /// then unwinding all three one step at a time.
        @Test func typeBoldTypeUnwindsOneStepAtATime() {
            let (textView, engine, window) = editor("<p>hello</p>")
            let original = html(engine)
            type(" there", textView, engine)
            let afterFirstTyping = html(engine)
            step(textView) {
                engine.selection = TextSelection(location: 0, length: 5)
                engine.apply(.toggleBold)
            }
            let afterBold = html(engine)
            type(" friend", textView, engine)
            #expect(textView.textStorage.string == "hello there friend")

            textView.undoManager?.undo()
            engine.synchronizeFromTextView()
            #expect(html(engine) == afterBold)

            textView.undoManager?.undo()
            #expect(html(engine) == afterFirstTyping)

            textView.undoManager?.undo()
            engine.synchronizeFromTextView()
            #expect(html(engine) == original)
            #expect(textView.undoManager?.canUndo == false)
            _ = window
        }

        /// Bold at a caret changes no characters, only what the next typing
        /// carries. It still has to end the typing run before it, or UIKit
        /// folds both runs into one undo step.
        @Test func boldAtACaretSeparatesTheTypingOnEitherSide() {
            let (textView, engine, window) = editor("<p></p>", groupsByEvent: true)
            keystrokes("word", textView, engine)
            engine.apply(.toggleBold)
            turnRunLoop()
            keystrokes(" another", textView, engine)
            #expect(textView.textStorage.string == "word another")

            // How UIKit splits a run of keystrokes into steps depends on timing,
            // so unwind everything rather than counting steps. What the engine
            // owes: the document passes through "word" twice in a row, once when
            // the second run goes and once when the toggle itself is undone.
            var texts: [String] = []
            while textView.undoManager?.canUndo == true, texts.count < 50 {
                textView.undoManager?.undo()
                texts.append(textView.textStorage.string)
            }

            let firstWord = texts.firstIndex(of: "word")
            #expect(firstWord.map { texts.dropFirst($0).prefix(2) == ["word", "word"] } == true)
            #expect(texts.last == "")
            _ = window
        }

        /// Undoing the typing after a caret Bold returns to the moment right
        /// after the tap, so Bold is still on. The next step, the toggle's own,
        /// then visibly turns it off rather than changing nothing.
        @Test func undoingTheTypingAfterACaretBoldLeavesBoldOn() {
            let (textView, engine, window) = editor("<p></p>", groupsByEvent: true)
            keystrokes("word ", textView, engine)
            engine.apply(.toggleBold)
            turnRunLoop()
            keystrokes("another", textView, engine)
            #expect(textView.textStorage.string == "word another")

            // Unwind everything: how UIKit splits a run of keystrokes into
            // steps depends on timing, so the test checks the states the
            // document passes through rather than counting steps.
            var states: [(text: String, bold: Bool)] = []
            while textView.undoManager?.canUndo == true, states.count < 50 {
                textView.undoManager?.undo()
                engine.synchronizeFromTextView()
                states.append((textView.textStorage.string, engine.typingAttributes.bold))
            }

            let atTap = states.firstIndex { $0.text == "word " }
            #expect(atTap.map { states[$0].bold } == true)
            #expect(atTap.map { states[$0 + 1].text == "word " && states[$0 + 1].bold == false } == true)
            #expect(states.last?.text == "")
            _ = window
        }

        /// The same sequence redone: the typing comes back plain, then redoing
        /// the toggle visibly turns Bold on again.
        @Test func redoingACaretBoldTurnsItBackOnInItsOwnStep() {
            let (textView, engine, window) = editor("<p></p>", groupsByEvent: true)
            keystrokes("word ", textView, engine)
            engine.apply(.toggleBold)
            turnRunLoop()
            keystrokes("another", textView, engine)
            while textView.undoManager?.canUndo == true {
                textView.undoManager?.undo()
                engine.synchronizeFromTextView()
            }
            #expect(textView.textStorage.string == "")

            var states: [(text: String, bold: Bool)] = []
            while textView.undoManager?.canRedo == true, states.count < 50 {
                textView.undoManager?.redo()
                engine.synchronizeFromTextView()
                states.append((textView.textStorage.string, engine.typingAttributes.bold))
            }

            let beforeTap = states.firstIndex { $0.text == "word " }
            #expect(beforeTap.map { states[$0].bold } == false)
            #expect(beforeTap.map { states[$0 + 1].text == "word " && states[$0 + 1].bold == true } == true)
            #expect(states.last?.text == "word another")
            _ = window
        }

        @Test func engineUndoTellsTheDelegateTheTextChanged() {
            let (textView, engine, window) = editor("<p>hello</p>")
            let delegate = ChangeCountingDelegate()
            textView.delegate = delegate
            step(textView) {
                engine.selection = TextSelection(location: 0, length: 5)
                engine.apply(.toggleBold)
            }
            #expect(delegate.changes == 0)

            textView.undoManager?.undo()

            // The SwiftUI coordinator publishes to the binding from
            // `textViewDidChange`, the same way it does after UIKit's own undo.
            #expect(delegate.changes == 1)
            _ = window
        }

        @Test func replacingTheDocumentStillDropsTheUndoStack() {
            let (textView, engine, window) = editor("<p>hello</p>")
            step(textView) {
                engine.selection = TextSelection(location: 0, length: 5)
                engine.apply(.toggleBold)
            }
            #expect(textView.undoManager?.canUndo == true)

            engine.text = RichTextHTML.decode("<h1>something else entirely</h1>")

            #expect(textView.undoManager?.canUndo == false)
            _ = window
        }
    }

    @MainActor
    private final class ChangeCountingDelegate: NSObject, UITextViewDelegate {
        var changes = 0

        func textViewDidChange(_: UITextView) {
            changes += 1
        }
    }
#endif
