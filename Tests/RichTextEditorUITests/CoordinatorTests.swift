// CoordinatorTests.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
import RichTextCore
import Testing

#if os(iOS)
    @testable import RichTextEditorUI
    import RichTextEngine
    import SwiftUI
    import UIKit

    /// The representable's coordinator: delegate wiring, echo suppression, and
    /// Return interception. Simulator-only.
    @MainActor
    struct CoordinatorTests {
        /// A `Binding` over a local box, so a test can see what the coordinator publishes.
        private final class Box { var value = AttributedString(); var writeCount = 0 }

        private func harness(_ html: String = "<p>hello</p>")
            -> (UITextView, Coordinator, Box, RichTextEditorModel, UIKitEditorEngine)
        {
            let box = Box()
            box.value = RichTextHTML.decode(html)
            let binding = Binding<AttributedString>(
                get: { box.value },
                set: { box.value = $0; box.writeCount += 1 }
            )
            let model = RichTextEditorModel()
            let textView = UITextView()
            let coordinator = Coordinator(text: binding, model: model)
            let engine = UIKitEditorEngine(textView: textView)
            engine.text = box.value
            textView.delegate = coordinator
            coordinator.attach(engine: engine)
            model.attach(engine)
            return (textView, coordinator, box, model, engine)
        }

        @Test func typingPublishesTheSemanticDocument() {
            let (textView, coordinator, box, _, _) = harness()
            textView.selectedRange = NSRange(location: 5, length: 0)
            textView.insertText("!")
            coordinator.textViewDidChange(textView)
            #expect(RichTextHTML.encode(box.value) == "<p>hello!</p>")
        }

        @Test func anEchoFromTheBindingIsNotPushedBackIntoTheEngine() {
            let (textView, coordinator, box, _, _) = harness()
            textView.selectedRange = NSRange(location: 5, length: 0)
            textView.insertText("!")
            coordinator.textViewDidChange(textView)

            let storageBefore = textView.textStorage.string
            // This is exactly what `updateUIView` does on the next SwiftUI turn.
            coordinator.pushIfNeeded(box.value)
            #expect(textView.textStorage.string == storageBefore)
            #expect(coordinator.pushedDocumentCount == 0)
        }

        @Test func agenuinelyNewDocumentFromTheBindingIsPushed() {
            let (textView, coordinator, _, _, _) = harness()
            coordinator.pushIfNeeded(RichTextHTML.decode("<h1>replaced</h1>"))
            #expect(textView.textStorage.string == "replaced")
            #expect(coordinator.pushedDocumentCount == 1)
        }

        @Test func bindingReceivesNormalizedLineEndingsFromInitialAndReplacementDocuments() async {
            let box = Box()
            box.value = AttributedString("first\r\nsecond")
            let binding = Binding<AttributedString>(
                get: { box.value },
                set: { box.value = $0; box.writeCount += 1 }
            )
            let model = RichTextEditorModel()
            let coordinator = Coordinator(text: binding, model: model)
            let engine = UIKitEditorEngine(textView: UITextView())
            engine.text = box.value
            coordinator.attach(engine: engine)
            model.attach(engine)

            await settle()
            #expect(String(box.value.characters) == "first\nsecond")
            #expect(box.writeCount == 1)

            box.value = AttributedString("third\rfourth")
            coordinator.pushIfNeeded(box.value)
            await settle()
            #expect(String(box.value.characters) == "third\nfourth")
            #expect(box.writeCount == 2)
            #expect(coordinator.pushedDocumentCount == 1)
            coordinator.pushIfNeeded(box.value)
            #expect(coordinator.pushedDocumentCount == 1)
        }

        @Test func aBindingThatDropsWritesDoesNotRepushAnUnnormalizedDocument() async {
            // `.constant(_:)` style: the setter is ignored, so every
            // `updateUIView` hands back the raw CRLF document.
            let raw = AttributedString("first\r\nsecond")
            let binding = Binding<AttributedString>(get: { raw }, set: { _ in })
            let model = RichTextEditorModel()
            let coordinator = Coordinator(text: binding, model: model)
            let engine = UIKitEditorEngine(textView: UITextView())
            engine.text = raw
            coordinator.attach(engine: engine)
            model.attach(engine)
            await settle()

            coordinator.pushIfNeeded(raw)
            await settle()
            coordinator.pushIfNeeded(raw)
            await settle()
            coordinator.pushIfNeeded(raw)
            #expect(coordinator.pushedDocumentCount == 0)
        }

        @Test func mountingADocumentWithExplicitBlackDoesNotWriteBack() async {
            let box = Box()
            box.value = AttributedString("dark")
            box.value.textColor = .black
            let binding = Binding<AttributedString>(
                get: { box.value },
                set: { box.value = $0; box.writeCount += 1 }
            )
            let model = RichTextEditorModel()
            let coordinator = Coordinator(text: binding, model: model)
            let engine = UIKitEditorEngine(textView: UITextView())
            engine.text = box.value
            coordinator.attach(engine: engine)
            model.attach(engine)
            await settle()

            #expect(engine.text.runs.first?.textColor == nil)
            #expect(box.writeCount == 0)
            coordinator.pushIfNeeded(box.value)
            #expect(coordinator.pushedDocumentCount == 0)
        }

        @Test func mountingACRLFDocumentWithExplicitBlackWritesBackOnlyTheLineEndings() async {
            let box = Box()
            box.value = AttributedString("first\r\nsecond")
            box.value.textColor = .black
            let binding = Binding<AttributedString>(
                get: { box.value },
                set: { box.value = $0; box.writeCount += 1 }
            )
            let model = RichTextEditorModel()
            let coordinator = Coordinator(text: binding, model: model)
            let engine = UIKitEditorEngine(textView: UITextView())
            engine.text = box.value
            coordinator.attach(engine: engine)
            model.attach(engine)
            await settle()

            #expect(box.writeCount == 1)
            #expect(String(box.value.characters) == "first\nsecond")
            #expect(box.value.runs.allSatisfy { $0.textColor == .black })
            coordinator.pushIfNeeded(box.value)
            #expect(coordinator.pushedDocumentCount == 0)
        }

        @Test func selectionChangesRefreshTheModelWithoutPublishing() async {
            let (textView, coordinator, box, model, _) = harness("<p><b>bold</b> plain</p>")
            let writesBefore = box.writeCount
            textView.selectedRange = NSRange(location: 0, length: 4)
            coordinator.textViewDidChangeSelection(textView)
            // `synchronizeSelection()` now defers its republish (Fix 1), so the
            // model's `formatState` reflects the new selection only after the hop.
            await settle()
            #expect(model.formatState.bold == .on)
            // A caret move is not a document change.
            #expect(box.writeCount == writesBefore)
        }

        @Test func returnIsInterceptedAndAppliesTheListPolicy() {
            let (textView, coordinator, box, model, _) = harness("<ul><li>one</li></ul>")
            textView.selectedRange = NSRange(location: 3, length: 0)
            let allowed = coordinator.textView(
                textView,
                shouldChangeTextIn: NSRange(location: 3, length: 0),
                replacementText: "\n"
            )
            // The coordinator performed the edit itself.
            #expect(allowed == false)
            #expect(textView.textStorage.string == "one\n")
            #expect(model.formatState.blockStyle == .listItem(.unordered, depth: 0))
            #expect(String(box.value.characters) == "one\n")
        }

        @Test func ordinaryTypingIsNotIntercepted() {
            let (textView, coordinator, _, _, _) = harness()
            let allowed = coordinator.textView(
                textView,
                shouldChangeTextIn: NSRange(location: 5, length: 0),
                replacementText: "x"
            )
            #expect(allowed == true)
        }

        @Test func typingAfterAnInterceptedReturnLandsInTheNewListItem() {
            let (textView, coordinator, _, model, _) = harness("<ul><li>one</li></ul>")
            textView.selectedRange = NSRange(location: 3, length: 0)
            _ = coordinator.textView(
                textView,
                shouldChangeTextIn: NSRange(location: 3, length: 0),
                replacementText: "\n"
            )
            textView.insertText("two")
            coordinator.textViewDidChange(textView)
            #expect(RichTextHTML.encode(model.text) == "<ul><li>one</li><li>two</li></ul>")
        }

        // MARK: - Fix 1: re-pointing the binding

        @Test func rebindingRedirectsSubsequentPublishesToTheNewBoxNotTheOld() {
            let (textView, coordinator, boxA, _, _) = harness()
            textView.selectedRange = NSRange(location: 5, length: 0)
            textView.insertText("!")
            coordinator.textViewDidChange(textView)
            #expect(RichTextHTML.encode(boxA.value) == "<p>hello!</p>")
            let boxAValueAfterFirstPublish = boxA.value

            // Simulate `updateUIView` re-pointing the coordinator's binding to a
            // *different* box — e.g. a parent view switching which document is
            // bound to the same `RichTextEditor` identity.
            let boxB = Box()
            boxB.value = RichTextHTML.decode("<p>separate</p>")
            let bindingB = Binding<AttributedString>(
                get: { boxB.value },
                set: { boxB.value = $0; boxB.writeCount += 1 }
            )
            coordinator.text = bindingB

            textView.insertText("?")
            coordinator.textViewDidChange(textView)

            #expect(RichTextHTML.encode(boxB.value) == "<p>hello!?</p>")
            // The old box must not have received the post-rebind edit.
            #expect(boxA.value == boxAValueAfterFirstPublish)
        }

        // MARK: - Fix 2: commands publish, and post-command reverts aren't echoes

        @Test func applyingACommandThroughTheModelPublishesToTheBinding() {
            // Keep the coordinator alive for the duration of the test: `delegate`
            // is a weak reference, so a discarded coordinator deallocates
            // immediately and its `[weak self]` `onDocumentChange` closure would
            // silently never fire — defeating the point of this test.
            let (_, coordinator, box, model, _) = harness()
            let writesBefore = box.writeCount
            model.apply(.toggleBold)
            #expect(box.writeCount == writesBefore + 1)
            #expect(coordinator.pushedDocumentCount == 0)
        }

        @Test func aConsumerRevertToThePreCommandDocumentIsAcceptedNotDroppedAsAnEcho() {
            let (textView, coordinator, box, model, _) = harness()
            let preCommandDocument = box.value

            textView.selectedRange = NSRange(location: 0, length: 5)
            model.apply(.toggleBold)
            // The command actually changed the published document (bolding
            // existing text), or this test would not distinguish a dropped
            // write from one that legitimately had nothing to do.
            #expect(box.value != preCommandDocument)

            // A consumer (e.g. a revert button) now deliberately writes the
            // *pre-command* document back through the binding itself — the
            // thing under test is what `updateUIView` -> `pushIfNeeded` does
            // with that write on the next SwiftUI turn, not whether
            // `pushIfNeeded` writes the box (it doesn't; the consumer already
            // did).
            box.value = preCommandDocument
            coordinator.pushIfNeeded(box.value)
            // Accepted into the engine (not silently dropped as an echo of the
            // command's own publish) — reflected back through the model's
            // pass-through `text`.
            #expect(coordinator.pushedDocumentCount == 1)
            #expect(RichTextHTML.encode(model.text) == RichTextHTML.encode(preCommandDocument))
        }

        // MARK: - Fix 3: Return during IME composition is not intercepted

        @Test func returnDuringIMECompositionIsNotInterceptedAndLeavesMarkedTextIntact() {
            let box = Box()
            box.value = RichTextHTML.decode("<p>hi</p>")
            let binding = Binding<AttributedString>(
                get: { box.value },
                set: { box.value = $0; box.writeCount += 1 }
            )
            let model = RichTextEditorModel()
            let textView = UITextView()
            // Marked text only works once the text view is in a key window and
            // first responder — see `InPlaceRenderingTests`.
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
            window.addSubview(textView)
            window.makeKeyAndVisible()
            textView.becomeFirstResponder()
            let coordinator = Coordinator(text: binding, model: model)
            let engine = UIKitEditorEngine(textView: textView)
            engine.text = box.value
            textView.delegate = coordinator
            coordinator.attach(engine: engine)
            model.attach(engine)

            textView.insertText("hi")
            engine.synchronizeFromTextView()
            textView.setMarkedText("あ", selectedRange: NSRange(location: 0, length: 1))
            // Load-bearing, per `InPlaceRenderingTests`: `setMarkedText` mutates
            // `textStorage` directly, bypassing the engine's `text` setter, so
            // the semantic document must be re-synced before asserting on it.
            engine.synchronizeFromTextView()
            #expect(textView.markedTextRange != nil)

            let allowed = coordinator.textView(
                textView,
                shouldChangeTextIn: NSRange(location: textView.text.count, length: 0),
                replacementText: "\n"
            )

            #expect(allowed == true)
            #expect(textView.markedTextRange != nil)
        }

        // MARK: - Fix 1: re-pointing the model

        @Test func rebindingTheModelReattachesTheEngineAndRewiresPublishing() async {
            let (textView, coordinator, box, modelA, _) = harness("<p><b>bold</b> plain</p>")
            // `harness()`'s own `model.attach(engine)` now schedules a deferred
            // republication; let it land before taking the
            // snapshot below, or it would fire later — during the settle after
            // `setModel` — and stomp `modelA`'s state out from under this test.
            await settle()
            let modelASnapshotBeforeRebind = modelA.formatState

            // `UIKitEditorEngine.selection`/`formatState` read the text view
            // live, so this selection is in place *before* the swap below —
            // proving `setModel` itself (not some subsequent selection-change
            // hook) is what makes the new model's `formatState` correct.
            textView.selectedRange = NSRange(location: 0, length: 4)

            // Simulate `updateUIView` swapping in a new model — e.g. the
            // `.richTextToolbar(...)` wrapper injecting its own `@State` model.
            // `setModel` is the single entry point `updateUIView` calls; it must
            // do all the re-wiring itself. Nothing here attaches the engine or
            // touches `onDocumentChange` by hand — that would just be testing
            // that manual wiring works, not that `setModel` does it.
            let modelB = RichTextEditorModel()
            coordinator.setModel(modelB)

            // `setModel` re-attaches the engine via `attach(_:)`, which now
            // defers its `formatState` republication off the update phase —
            // `setModel` itself runs from `updateUIView`, so this
            // matches production. Await the hop before asserting.
            await settle()
            #expect(modelB.formatState.bold == .on)

            // A command through the new model reaches the document...
            let writesBefore = box.writeCount
            modelB.apply(.toggleItalic)
            #expect(modelB.formatState.italic == .on)
            // ...and does so via the re-wired `onDocumentChange` publishing to
            // the binding, not by some other path.
            #expect(box.writeCount == writesBefore + 1)

            // The old model is inert: a post-rebind selection change is routed
            // to the coordinator's current model (modelB) and never reaches it.
            textView.selectedRange = NSRange(location: 5, length: 5)
            coordinator.textViewDidChangeSelection(textView)
            #expect(modelA.formatState == modelASnapshotBeforeRebind)
        }
    }

    extension CoordinatorTests {
        @Test func reassigningTheOriginalUnnormalizedDocumentIsWrittenBackAgain() async {
            let raw = AttributedString("first\r\nsecond")
            let box = Box()
            box.value = raw
            let binding = Binding<AttributedString>(
                get: { box.value },
                set: { box.value = $0; box.writeCount += 1 }
            )
            let model = RichTextEditorModel()
            let coordinator = Coordinator(text: binding, model: model)
            let engine = UIKitEditorEngine(textView: UITextView())
            engine.text = box.value
            coordinator.attach(engine: engine)
            model.attach(engine)
            await settle()
            #expect(String(box.value.characters) == "first\nsecond")

            box.value = raw
            coordinator.pushIfNeeded(box.value)
            await settle()
            #expect(String(box.value.characters) == "first\nsecond")
            #expect(box.writeCount == 2)
        }
    }
#endif
