// UIKitEditorEngine+Undo.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

#if canImport(UIKit)
    import RichTextCore
    import UIKit

    extension UIKitEditorEngine {
        /// Everything an engine edit changes, so undo can put it all back.
        struct UndoSnapshot {
            let text: AttributedString
            let typingAttributes: TypingAttributes
            let selection: TextSelection
        }

        func undoSnapshot() -> UndoSnapshot {
            UndoSnapshot(text: semanticText, typingAttributes: typingAttributes, selection: selection)
        }

        /// Engine edits write `textStorage` directly and never pass through
        /// `shouldChangeTextIn:`, where UIKit registers undo for typing, so they
        /// register their own entry on the same stack. Each entry restores the
        /// whole pre-edit document rather than inverting the command, which
        /// keeps the stack consistent however the two kinds interleave: undoing
        /// an engine entry puts back exactly the document the older UIKit
        /// entries beneath it describe.
        ///
        /// The target is the text view, which owns this undo manager and so
        /// outlives every entry; the engine is captured weakly because the
        /// undo manager does not retain its targets.
        func registerUndo(restoring snapshot: UndoSnapshot) {
            textView.undoManager?.registerUndo(withTarget: textView) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.restore(snapshot)
                }
            }
        }

        /// Registers undo for a command that took the engine from `before` to
        /// `result`, if it changed anything.
        ///
        /// A command at a caret changes only the typing attributes, but it
        /// still needs its own entry: without one on the stack, UIKit folds the
        /// typing before and after it into a single undo step. For that step to
        /// change something visible, the typing attributes the command set have
        /// to survive UIKit's undo of the typing that followed, so the state
        /// right after the command is kept too (see
        /// `restoreCaretCommandTypingAttributes()`).
        func recordUndo(restoring before: UndoSnapshot, for result: EditResult) {
            guard result.text != before.text || result.typingAttributes != before.typingAttributes else {
                return
            }
            registerUndo(restoring: before)
            if result.text == before.text {
                rememberCaretCommandState(of: result)
            }
        }

        /// Keeps the state right after an engine edit whose typing attributes
        /// hold something the text can't: a caret command's choice, or the
        /// pending block style of the empty block a Return opens (D13). Undoing
        /// the typing that followed re-derives the typing attributes from the
        /// text and would lose it; `restoreCaretCommandTypingAttributes()`
        /// brings it back when the document lands on this state again.
        func rememberCaretCommandState(of result: EditResult) {
            let after = UndoSnapshot(
                text: result.text,
                typingAttributes: result.typingAttributes,
                selection: result.selection
            )
            caretCommandStates.append(after)
            if caretCommandStates.count > Self.caretCommandStateLimit {
                caretCommandStates.removeFirst()
            }
        }

        /// Called by `insertNewline()`: a Return that opens an empty block
        /// with a pending block style (a new list item, say) leaves a state
        /// the typing after it can't describe (GitHub issue #21).
        func rememberPendingBlockStyleState(of result: EditResult) {
            if result.typingAttributes.blockStyle != nil {
                rememberCaretCommandState(of: result)
            }
        }

        /// How many caret-command states are kept. Each is a whole-document
        /// snapshot, though `AttributedString` shares storage between them.
        private static let caretCommandStateLimit = 20

        /// Called after `synchronizeFromTextView()` re-derives the typing
        /// attributes from the text. Deriving reads the characters before the
        /// caret, which after an undo of "type, Bold, type" is the plain text
        /// before the tap, so Bold would go off one step early and leave the
        /// toggle's own step with nothing to change. When the document and
        /// caret are exactly as a caret command left them, its typing
        /// attributes are what the user last chose there, so they come back.
        /// Backspacing to that point by hand lands on the same state and gets
        /// the same result.
        func restoreCaretCommandTypingAttributes() {
            let current = selection
            if let state = caretCommandStates.last(where: { $0.selection == current && $0.text == semanticText }) {
                typingAttributes = state.typingAttributes
            }
        }

        /// Keeps `caretCommandStates` in step with the stack. Undoing a caret
        /// command leaves the state it created, so that state stops counting:
        /// otherwise the sync after the undo would find it and turn Bold straight
        /// back on, and redoing the typing before the command would turn it on a
        /// step early. Redoing the command makes its state count again.
        ///
        /// Only the latest matching state is the undone command's own. An older
        /// one at the same document and caret (an earlier command there, or the
        /// Return that opened an empty block) still describes a step on the
        /// stack, so it stays.
        private func trackCaretCommandState(from current: UndoSnapshot, to snapshot: UndoSnapshot) {
            guard snapshot.text == current.text, let undoManager = textView.undoManager else {
                return
            }
            if undoManager.isUndoing {
                if let latest = caretCommandStates.lastIndex(where: {
                    $0.text == current.text && $0.selection == current.selection
                }) {
                    caretCommandStates.remove(at: latest)
                }
            } else if undoManager.isRedoing {
                caretCommandStates.append(snapshot)
            }
        }

        private func restore(_ snapshot: UndoSnapshot) {
            // Registered while the undo manager is undoing, so it lands on the
            // redo stack (and back on the undo stack during a redo).
            let current = undoSnapshot()
            registerUndo(restoring: current)
            trackCaretCommandState(from: current, to: snapshot)
            semanticText = snapshot.text
            typingAttributes = snapshot.typingAttributes
            render(restoring: snapshot.selection)
            lastAttributesSelection = selection
            pushTypingAttributes()
            // UIKit reports its own undo of typing through `textViewDidChange`;
            // an engine undo has to say so itself, or the SwiftUI coordinator
            // never publishes the restored document to the binding.
            textView.delegate?.textViewDidChange?(textView)
        }
    }
#endif
