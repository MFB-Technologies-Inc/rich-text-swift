// ToolbarEndToEndTests.swift
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

    /// The full v1 toolbar works end to
    /// end through the `RichTextEditorModel` seam, with no control touching the
    /// text view.
    @MainActor
    struct ToolbarEndToEndTests {
        private let fullControlSet: [RichTextControl] = [
            .bold, .italic, .underline, .strikethrough, .textColor,
            .unorderedList, .orderedList, .heading(.h1), .heading(.h2), .heading(.h3),
        ]

        private func findTextView(in view: UIView) -> UITextView? {
            if let textView = view as? UITextView {
                return textView
            }
            for sub in view.subviews {
                if let found = findTextView(in: sub) {
                    return found
                }
            }
            return nil
        }

        /// Hosts the editor plus the full toolbar and returns the pieces a test
        /// needs: the toolbar (to tap), the shared model, and the live text view.
        private func session(html: String) async -> (RichTextToolbar, RichTextEditorModel, UITextView) {
            let model = RichTextEditorModel()
            let root = RichTextEditor(text: .constant(RichTextHTML.decode(html)))
                .richTextToolbar(fullControlSet, model: model)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
            window.rootViewController = UIHostingController(rootView: root)
            window.makeKeyAndVisible()
            window.layoutIfNeeded()
            await settle()
            window.layoutIfNeeded()
            await settle()
            let textView = findTextView(in: window)!
            return (RichTextToolbar(controls: fullControlSet, model: model), model, textView)
        }

        /// Selects a range the way a user would, then tells the engine about it —
        /// the same pair of steps the coordinator's delegate hook performs.
        /// `synchronizeSelection()` defers its `formatState` republish (Fix 1: it
        /// can be reached from the view-update phase via a reentrant
        /// `textViewDidChangeSelection`), so this awaits the hop before returning
        /// — every call site here wants the settled result, not the pre-hop one.
        private func select(_ range: NSRange, in textView: UITextView, _ model: RichTextEditorModel) async {
            textView.selectedRange = range
            model.synchronizeSelection()
            await settle()
        }

        @Test func aFullToolbarSessionProducesCleanHTML() async {
            let (toolbar, model, textView) = await session(html: "<p>Title</p><p>body text</p>")

            // Make the first block a heading.
            await select(NSRange(location: 0, length: 5), in: textView, model)
            toolbar.tap(.heading(.h1))

            // Bold part of the second block.
            await select(NSRange(location: 6, length: 4), in: textView, model)
            toolbar.tap(.bold)

            #expect(RichTextHTML.encode(model.text) == "<h1>Title</h1>\n<p><b>body</b> text</p>")
        }

        @Test func everyInlineControlRoundTripsThroughTheToolbar() async {
            let (toolbar, model, textView) = await session(html: "<p>abc</p>")
            await select(NSRange(location: 0, length: 3), in: textView, model)

            toolbar.tap(.bold)
            toolbar.tap(.italic)
            toolbar.tap(.underline)
            toolbar.tap(.strikethrough)

            #expect(RichTextHTML.encode(model.text) == "<p><b><i><u><s>abc</s></u></i></b></p>")
            // And the toolbar now reads all four as active.
            for control in [RichTextControl.bold, .italic, .underline, .strikethrough] {
                #expect(control.isActive(in: model.formatState), "\(control) should be active")
            }
        }

        @Test func listControlsTurnBlocksIntoListsAndBack() async {
            let (toolbar, model, textView) = await session(html: "<p>one</p><p>two</p>")
            await select(NSRange(location: 0, length: 7), in: textView, model)

            toolbar.tap(.unorderedList)
            #expect(RichTextHTML.encode(model.text) == "<ul><li>one</li><li>two</li></ul>")

            toolbar.tap(.orderedList)
            #expect(RichTextHTML.encode(model.text) == "<ol><li>one</li><li>two</li></ol>")

            toolbar.tap(.orderedList)
            #expect(RichTextHTML.encode(model.text) == "<p>one</p>\n<p>two</p>")
        }

        @Test func headingControlsToggleAndSwitchLevels() async {
            let (toolbar, model, textView) = await session(html: "<p>Title</p>")
            await select(NSRange(location: 0, length: 5), in: textView, model)

            toolbar.tap(.heading(.h1))
            #expect(RichTextHTML.encode(model.text) == "<h1>Title</h1>")

            toolbar.tap(.heading(.h3))
            #expect(RichTextHTML.encode(model.text) == "<h3>Title</h3>")

            toolbar.tap(.heading(.h3))
            #expect(RichTextHTML.encode(model.text) == "<p>Title</p>")
        }

        @Test func theColorControlAppliesAndRemovesColor() async {
            let (_, model, textView) = await session(html: "<p>abc</p>")
            await select(NSRange(location: 0, length: 3), in: textView, model)
            let menu = TextColorControl(model: model, isActive: false)

            menu.select(RichTextColor(red: 255, green: 59, blue: 48))
            #expect(RichTextHTML.encode(model.text) == "<p><span style=\"color:#ff3b30\">abc</span></p>")

            menu.select(nil)
            #expect(RichTextHTML.encode(model.text) == "<p>abc</p>")
        }

        @Test func anEditedDocumentStillSurvivesASerializationRoundTrip() async {
            let (toolbar, model, textView) = await session(html: "<p>abc</p><p>def</p>")
            await select(NSRange(location: 0, length: 3), in: textView, model)
            toolbar.tap(.heading(.h2))
            await select(NSRange(location: 4, length: 3), in: textView, model)
            toolbar.tap(.unorderedList)
            toolbar.tap(.italic)

            #expect(RichTextHTML.decode(RichTextHTML.encode(model.text)) == model.text)
        }

        @Test func theToolbarStateFollowsTheSelection() async {
            let (toolbar, model, textView) = await session(html: "<h1>Title</h1><p>body</p>")

            await select(NSRange(location: 0, length: 5), in: textView, model)
            #expect(RichTextControl.heading(.h1).isActive(in: model.formatState))

            await select(NSRange(location: 6, length: 4), in: textView, model)
            #expect(RichTextControl.heading(.h1).isActive(in: model.formatState) == false)

            toolbar.tap(.bold)
            #expect(RichTextControl.bold.isActive(in: model.formatState))
        }
    }
#endif
