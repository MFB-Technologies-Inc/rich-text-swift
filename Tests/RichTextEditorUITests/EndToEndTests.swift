// EndToEndTests.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
import RichTextCore
import Testing

#if canImport(UIKit)
    @testable import RichTextEditorUI
    import RichTextEngine
    import SwiftUI
    import UIKit

    /// The milestone's exit criterion, exercised the way a consumer would:
    /// a document goes in, edits happen through the view model and the text view,
    /// and clean HTML comes out.
    @MainActor
    struct EndToEndTests {
        private final class Box { var value = AttributedString() }

        private func harness(_ html: String) -> (UITextView, Coordinator, RichTextEditorModel, Box) {
            let box = Box()
            box.value = RichTextHTML.decode(html)
            let binding = Binding<AttributedString>(get: { box.value }, set: { box.value = $0 })
            let model = RichTextEditorModel()
            let textView = UITextView()
            let coordinator = Coordinator(text: binding, model: model)
            let engine = UIKitEditorEngine(textView: textView)
            engine.text = box.value
            textView.delegate = coordinator
            coordinator.attach(engine: engine)
            model.attach(engine)
            return (textView, coordinator, model, box)
        }

        @Test func aFullEditingSessionRoundTripsToCleanHTML() {
            let (textView, coordinator, model, box) = harness("<p>Title</p>")

            // Make it a heading.
            textView.selectedRange = NSRange(location: 0, length: 5)
            coordinator.textViewDidChangeSelection(textView)
            model.apply(.toggleHeading(1))

            // Type a new line: Return at the end of a heading starts a paragraph.
            textView.selectedRange = NSRange(location: 5, length: 0)
            _ = coordinator.textView(
                textView,
                shouldChangeTextIn: NSRange(location: 5, length: 0),
                replacementText: "\n"
            )
            textView.insertText("body")
            coordinator.textViewDidChange(textView)

            // Bold part of the body.
            textView.selectedRange = NSRange(location: 6, length: 4)
            coordinator.textViewDidChangeSelection(textView)
            model.apply(.toggleBold)

            #expect(RichTextHTML.encode(model.text) == "<h1>Title</h1>\n<p><b>body</b></p>")
            #expect(RichTextHTML.encode(box.value) == "<h1>Title</h1>\n<p><b>body</b></p>")
        }

        @Test func listEntryContinuesAcrossReturnsAndExitsOnAnEmptyItem() {
            let (textView, coordinator, model, _) = harness("<p>one</p>")

            textView.selectedRange = NSRange(location: 3, length: 0)
            coordinator.textViewDidChangeSelection(textView)
            model.apply(.toggleList(.unordered))

            _ = coordinator.textView(
                textView,
                shouldChangeTextIn: NSRange(location: 3, length: 0),
                replacementText: "\n"
            )
            textView.insertText("two")
            coordinator.textViewDidChange(textView)
            #expect(RichTextHTML.encode(model.text) == "<ul><li>one</li><li>two</li></ul>")

            // Return on the (now empty) third item leaves the list.
            _ = coordinator.textView(
                textView,
                shouldChangeTextIn: NSRange(location: 7, length: 0),
                replacementText: "\n"
            )
            _ = coordinator.textView(
                textView,
                shouldChangeTextIn: NSRange(location: 8, length: 0),
                replacementText: "\n"
            )
            #expect(model.formatState.blockStyle == .paragraph)
        }

        @Test func theDocumentSurvivesASerializationRoundTripAfterEditing() {
            let (textView, coordinator, model, _) = harness("<p>abc</p>")
            textView.selectedRange = NSRange(location: 0, length: 3)
            coordinator.textViewDidChangeSelection(textView)
            model.apply(.toggleItalic)
            model.apply(.setTextColor(RichTextColor(red: 255, green: 0, blue: 0)))
            #expect(RichTextHTML.decode(RichTextHTML.encode(model.text)) == model.text)
        }

        @Test func aConsumerReplacingTheDocumentIsAdopted() {
            let (textView, coordinator, model, _) = harness("<p>old</p>")
            coordinator.pushIfNeeded(RichTextHTML.decode("<h2>new</h2>"))
            #expect(textView.textStorage.string == "new")
            #expect(RichTextHTML.encode(model.text) == "<h2>new</h2>")
        }
    }
#endif
