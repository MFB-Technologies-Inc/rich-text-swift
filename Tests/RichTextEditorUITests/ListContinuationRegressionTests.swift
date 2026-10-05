// ListContinuationRegressionTests.swift
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
    import SwiftUI
    import UIKit

    /// The reported sequence: start a numbered list, Return, type, Return again.
    /// The second item must keep its number and the third must appear — a bug
    /// report described the second item's marker vanishing and the list ending.
    /// It did not reproduce, so this pins the whole loop rather than one call:
    /// `shouldChangeTextIn` (Return interception), `textViewDidChange`,
    /// `textViewDidChangeSelection`, and the SwiftUI turn that echoes the binding
    /// back through `updateUIView`.
    @MainActor
    struct ListContinuationRegressionTests {
        private final class Box { var value = AttributedString() }

        private struct Harness {
            let textView: UITextView
            let coordinator: Coordinator
            let engine: UIKitEditorEngine
            let model: RichTextEditorModel
            let box: Box
            let window: UIWindow
        }

        private func makeHarness(_ html: String) async -> Harness {
            let box = Box()
            box.value = RichTextHTML.decode(html)
            let binding = Binding<AttributedString>(get: { box.value }, set: { box.value = $0 })
            let model = RichTextEditorModel()
            let textView = UITextView(frame: CGRect(x: 0, y: 0, width: 320, height: 220))
            let window = UIWindow(frame: textView.frame)
            window.addSubview(textView)
            window.makeKeyAndVisible()
            let coordinator = Coordinator(text: binding, model: model)
            let engine = UIKitEditorEngine(textView: textView)
            engine.text = box.value
            textView.delegate = coordinator
            coordinator.attach(engine: engine)
            model.attach(engine)
            await settle()
            return Harness(
                textView: textView, coordinator: coordinator, engine: engine,
                model: model, box: box, window: window
            )
        }

        /// Every marker currently drawn, fragment by fragment, in document order.
        private func drawnMarkers(_ harness: Harness) -> [String] {
            harness.textView.layoutIfNeeded()
            var markers: [String] = []
            guard let manager = harness.textView.textLayoutManager,
                  let content = manager.textContentManager else { return markers }
            manager.enumerateTextLayoutFragments(from: content.documentRange.location) { fragment in
                if let fragment = fragment as? ListMarkerFragment {
                    markers += fragment.lineMarkers.sorted { $0.key < $1.key }.map(\.value.text)
                }
                return true
            }
            return markers
        }

        /// Presses Return at the caret the way the text view does.
        private func pressReturn(_ harness: Harness) {
            let caret = harness.textView.selectedRange.location
            _ = harness.coordinator.textView(
                harness.textView,
                shouldChangeTextIn: NSRange(location: caret, length: 0),
                replacementText: "\n"
            )
            // The SwiftUI turn: the published document comes back through updateUIView.
            harness.coordinator.pushIfNeeded(harness.box.value)
        }

        private func type(_ text: String, _ harness: Harness) {
            harness.textView.insertText(text)
            harness.coordinator.textViewDidChange(harness.textView)
            harness.coordinator.textViewDidChangeSelection(harness.textView)
            harness.coordinator.pushIfNeeded(harness.box.value)
        }

        @Test func returnTypeReturnKeepsNumberingAndStaysInTheList() async {
            let harness = await makeHarness("<ol><li>one</li></ol>")
            harness.textView.selectedRange = NSRange(location: 3, length: 0)
            harness.coordinator.textViewDidChangeSelection(harness.textView)

            pressReturn(harness)
            #expect(drawnMarkers(harness) == ["1.", "2."], "the next number must appear before typing")

            type("two", harness)
            #expect(drawnMarkers(harness) == ["1.", "2."], "typing must not drop the item's number")
            #expect(RichTextHTML.encode(harness.model.text) == "<ol><li>one</li><li>two</li></ol>")

            pressReturn(harness)
            #expect(drawnMarkers(harness) == ["1.", "2.", "3."], "the second Return must continue the list")
            #expect(harness.engine.typingAttributes.blockStyle == .listItem(.ordered, depth: 0))
        }

        @Test func returnOnAnEmptyItemStillLeavesTheList() async {
            // The neighbouring rule: a Return with nothing typed exits instead of
            // adding another item.
            let harness = await makeHarness("<ol><li>one</li></ol>")
            harness.textView.selectedRange = NSRange(location: 3, length: 0)
            harness.coordinator.textViewDidChangeSelection(harness.textView)

            pressReturn(harness)
            pressReturn(harness)

            #expect(drawnMarkers(harness) == ["1."])
            #expect(harness.engine.typingAttributes.blockStyle == nil)
        }

        @Test func theSameSequenceWorksForABulletedList() async {
            let harness = await makeHarness("<ul><li>one</li></ul>")
            harness.textView.selectedRange = NSRange(location: 3, length: 0)
            harness.coordinator.textViewDidChangeSelection(harness.textView)

            pressReturn(harness)
            type("two", harness)
            pressReturn(harness)

            #expect(drawnMarkers(harness) == ["•", "•", "•"])
            // The trailing empty block encodes as <p></p>: the third bullet is a
            // *pending* role, which is rendering-only and deliberately absent from
            // the document until a character exists to carry it.
            #expect(
                RichTextHTML.encode(harness.model.text) == "<ul><li>one</li><li>two</li></ul>\n<p></p>"
            )
        }
    }
#endif
