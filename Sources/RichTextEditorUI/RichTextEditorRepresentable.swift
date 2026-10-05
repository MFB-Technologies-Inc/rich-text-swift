// RichTextEditorRepresentable.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

#if os(iOS)
    import RichTextCore
    import RichTextEngine
    import SwiftUI
    import UIKit

    /// The thin View half of MVVM: it builds a `UITextView`, hands it to the
    /// engine, and forwards the text view's delegate callbacks to the model. It
    /// makes no formatting decisions of its own.
    struct RichTextEditorRepresentable: UIViewRepresentable {
        @Binding var text: AttributedString
        let model: RichTextEditorModel
        let isEditable: Bool
        /// Forces pasted content to plain text, mirrored onto the text view
        /// itself (`RichTextTextView.pasteAsPlainText`) rather than acted on
        /// here — `paste(_:)` is the text view's own responder method.
        let pasteAsPlainText: Bool

        /// The text view's own insets, shared so the placeholder overlay can line
        /// up with the first glyph rather than guessing.
        static let containerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
        /// `UITextView`'s default line-fragment padding, which sits inside the inset.
        static let lineFragmentPadding: CGFloat = 5
        static var textLeadingInset: CGFloat {
            containerInset.left + lineFragmentPadding
        }

        static var textTopInset: CGFloat {
            containerInset.top
        }

        static var bodyFontSize: CGFloat {
            CGFloat(Theme.default.paragraph.fontSize)
        }

        func makeCoordinator() -> Coordinator {
            Coordinator(text: $text, model: model)
        }

        func makeUIView(context: Context) -> RichTextTextView {
            let textView = RichTextTextView()
            textView.pasteAsPlainText = pasteAsPlainText
            textView.backgroundColor = .clear
            textView.alwaysBounceVertical = true
            textView.textContainerInset = Self.containerInset

            let engine = UIKitEditorEngine(textView: textView)
            engine.text = text
            textView.engine = engine
            context.coordinator.attach(engine: engine)
            model.attach(engine)
            // Set the delegate only once the engine (and therefore the
            // coordinator's own `engine` reference) exists — `attach(engine:)`'s
            // initial render otherwise re-enters `textViewDidChangeSelection`
            // against a coordinator whose `engine` is still nil.
            textView.isEditable = isEditable
            model.setEditable(isEditable)
            textView.delegate = context.coordinator
            return textView
        }

        func updateUIView(_ textView: RichTextTextView, context: Context) {
            textView.pasteAsPlainText = pasteAsPlainText
            // A `Binding` closes over the storage current when it was captured.
            // SwiftUI can hand the *same* coordinator a differently-scoped
            // `$text` across updates (e.g. a parent switching which document is
            // bound in), so the coordinator's binding must be re-pointed here on
            // every update rather than captured once in `makeCoordinator()`.
            context.coordinator.text = $text
            context.coordinator.setModel(model)
            // Both are no-ops when unchanged: `setEditable` guards, and assigning
            // an equal `isEditable` does not disturb the text view.
            if textView.isEditable != isEditable {
                textView.isEditable = isEditable
            }
            model.setEditable(isEditable)
            context.coordinator.pushIfNeeded(text)
        }
    }

    /// Owns the binding write-back and the text view's delegate contract.
    ///
    /// The wiring is the one M3's `UIKitEditorEngine` documents, and both hooks are
    /// required: `textViewDidChangeSelection` -> `synchronizeSelection()` (cheap,
    /// keeps a pending block style correct on every caret move) and
    /// `textViewDidChange` -> `synchronizeFromTextView()` (pulls the document back
    /// out of storage after real typing or pasting).
    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        /// Mutable, not `let`: a `Binding` is a value type closing over the
        /// storage current at capture time. `updateUIView` re-points this to
        /// `$text` on every SwiftUI update, so a parent that swaps which
        /// document is bound (same view identity, same coordinator) still
        /// writes edits back into the *current* box rather than a stale one.
        var text: Binding<AttributedString> {
            didSet { bindingRevision += 1 }
        }

        private var bindingRevision = 0
        /// A binding may discard normalized writes and return the same raw
        /// document on every update. Bound retries per raw document so that
        /// write-back cannot keep driving SwiftUI updates indefinitely.
        private var lastWriteBackDocument: AttributedString?
        private var writeBackAttempts = 0
        private var writeBackRevision = 0
        private static let maxWriteBackAttempts = 3
        /// SwiftUI can hand this coordinator a differently-scoped `model` across
        /// updates (e.g. M5's injected model swapping in). Settable only through
        /// `setModel(_:)` below — never assigned directly — because a swap has
        /// to re-attach the engine and re-wire `onDocumentChange`, not just
        /// re-point the reference.
        private(set) var model: RichTextEditorModel
        private var engine: UIKitEditorEngine?

        /// The last document published to the binding. SwiftUI hands it straight
        /// back on the next turn via `updateUIView`; pushing it into the engine
        /// would be a pure echo (M4 decision D4). The engine has its own
        /// idempotence guard, but suppressing here avoids the whole round trip.
        private var lastPublished: AttributedString?

        /// The last binding document adopted into the engine, before
        /// normalization. A binding that drops writes (`.constant(_:)`) keeps
        /// handing back this raw document, which matches neither
        /// `lastPublished` nor `engine.text` once line endings are normalized.
        /// Cleared on `publish()` and once the binding accepts a line-ending
        /// write-back, so a consumer reverting to it afterwards is still pushed.
        /// Matching it skips the engine push but still retries the write-back.
        private var lastAdopted: AttributedString?

        /// Counts documents actually pushed into the engine from the binding, so
        /// tests can prove an echo was suppressed rather than merely harmless.
        private(set) var pushedDocumentCount = 0

        init(text: Binding<AttributedString>, model: RichTextEditorModel) {
            self.text = text
            self.model = model
        }

        func attach(engine: UIKitEditorEngine) {
            self.engine = engine
            lastPublished = engine.text
            lastAdopted = text.wrappedValue
            wireOnDocumentChange()
            writeBackNormalizationIfNeeded(for: text.wrappedValue, normalized: engine.text)
        }

        /// `updateUIView`'s entry point for a model swap (Fix 1): re-points
        /// `model`, re-attaches the (unchanged) engine to it, and re-wires
        /// `onDocumentChange` — the three things `makeUIView` does once for
        /// whichever model is current when the platform view is built, and
        /// which nothing re-ran on a later swap before this method existed.
        /// Guarded by identity so an unchanged model (the common case, called on
        /// every SwiftUI update) does no work.
        func setModel(_ newModel: RichTextEditorModel) {
            guard newModel !== model else {
                return
            }
            // The old model must not keep publishing for a text view it no
            // longer drives.
            model.onDocumentChange = nil
            model = newModel
            if let engine {
                model.attach(engine)
            }
            wireOnDocumentChange()
        }

        /// Commands (`apply(_:)`) and `insertNewline()` mutate the engine
        /// directly, so `UITextViewDelegate.textViewDidChange` never fires for
        /// them and the result never reaches the binding (M4 fix wave).
        /// `[weak self]`: the model is held by the view, the coordinator by
        /// SwiftUI — neither owns the other, but capturing strongly here would
        /// still be a cycle via the closure the model retains.
        private func wireOnDocumentChange() {
            model.onDocumentChange = { [weak self] in self?.publish() }
        }

        /// `updateUIView`'s entry point: adopt a document the *consumer* changed,
        /// and ignore one this coordinator just published.
        func pushIfNeeded(_ incoming: AttributedString) {
            guard let engine else {
                return
            }
            if incoming != lastAdopted {
                writeBackRevision += 1
            }
            // A later return to the same raw document is a new write-back
            // opportunity after another document has been displayed.
            if let lastWriteBackDocument, incoming != lastWriteBackDocument {
                self.lastWriteBackDocument = nil
                writeBackAttempts = 0
            }
            guard incoming != lastPublished, incoming != engine.text else {
                return
            }
            // The raw document already in the engine: don't push it again, but
            // retry the write-back. `updateUIView` may have re-pointed `text` to
            // a different binding (a `Binding` has no identity to compare), and
            // the task queued for the old one never reaches the new one. The
            // task's own guard makes the retry a no-op once a write lands.
            if incoming == lastAdopted {
                writeBackNormalizationIfNeeded(for: incoming, normalized: engine.text)
                return
            }
            pushedDocumentCount += 1
            // Match `publish()`'s ordering: record `lastPublished` before
            // handing the document to the engine, so a re-entrant read during
            // `engine.text`'s setter never observes a stale `lastPublished`.
            lastPublished = incoming
            lastAdopted = incoming
            // Routed through the model (Fix 3), not `engine.text = incoming`
            // directly: `setText(_:)` already does this-plus-`refresh()`, and
            // the MVVM invariant is that everything flows through the model.
            model.setText(incoming)
            lastPublished = engine.text
            writeBackNormalizationIfNeeded(for: incoming, normalized: engine.text)
        }

        private func writeBackNormalizationIfNeeded(for incoming: AttributedString, normalized: AttributedString) {
            // Only line endings are written back: they change the characters,
            // so the binding would otherwise disagree with the editor about
            // block boundaries. Stripping an explicit black `textColor` is
            // invisible, and writing it back would mark the consumer's document
            // dirty just for opening it.
            guard !incoming.characters.elementsEqual(normalized.characters) else { return }
            // `normalized` is the engine's document, which has black stripped
            // too, so the binding gets `incoming` with only its line endings
            // rewritten.
            let lineEndingsOnly = LineEndings.normalized(incoming)
            // These paths can run inside a SwiftUI view update. Publish on the
            // next turn without overwriting a newer consumer or engine edit.
            let binding = text
            let revision = bindingRevision
            let documentRevision = writeBackRevision
            Task { @MainActor [weak self] in
                guard let self, bindingRevision == revision, writeBackRevision == documentRevision,
                      binding.wrappedValue == incoming, engine?.text == normalized else { return }
                if lastWriteBackDocument != incoming {
                    lastWriteBackDocument = incoming
                    writeBackAttempts = 0
                }
                guard writeBackAttempts < Self.maxWriteBackAttempts else { return }
                writeBackAttempts += 1
                lastPublished = lineEndingsOnly
                binding.wrappedValue = lineEndingsOnly
                // A binding may reconstruct or restyle its value on read. It
                // accepted the line-ending write when its characters now match
                // the written characters, even if its attributes differ.
                if binding.wrappedValue.characters.elementsEqual(lineEndingsOnly.characters) {
                    lastAdopted = nil
                    lastWriteBackDocument = nil
                    writeBackAttempts = 0
                }
            }
        }

        private func publish() {
            guard let engine else {
                return
            }
            lastWriteBackDocument = nil
            writeBackAttempts = 0
            writeBackRevision += 1
            lastPublished = engine.text
            lastAdopted = nil
            text.wrappedValue = engine.text
        }

        // MARK: - UITextViewDelegate

        func textViewDidChange(_: UITextView) {
            model.synchronizeFromTextView()
            publish()
        }

        func textViewDidChangeSelection(_: UITextView) {
            model.synchronizeSelection()
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText replacement: String
        ) -> Bool {
            // Only Return is intercepted: the engine owns the block-role policy
            // (M4 decision D5), which a plain newline insertion would silently drop.
            guard replacement == "\n", let engine else { return true }
            // During IME composition (CJK), Return is the commit key, not a
            // newline. `UIKitEditorEngine.render(restoring:)` warns that a
            // whole-storage reassignment (the character-changing render path,
            // which inserting a newline always takes) destroys in-progress
            // marked text. Let UIKit commit the composition normally instead of
            // intercepting.
            guard textView.markedTextRange == nil else { return true }
            engine.selection = TextSelection(location: range.location, length: range.length)
            model.insertNewline()
            // `model.insertNewline()` publishes via `onDocumentChange` (fix
            // wave), so no explicit `publish()` here.
            // UIKit's own insertion scrolls the caret into view; the engine's
            // direct `selectedRange` assignment does not, so a Return at the
            // bottom of a long document would otherwise leave the caret
            // off-screen.
            textView.scrollRangeToVisible(textView.selectedRange)
            return false
        }
    }
#endif
