// RichPasteTests.swift
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

    /// The default paste: pasteboard HTML is decoded into the
    /// semantic model and inserted through the engine, so pasted bold and
    /// headings survive and the view shows the theme, not the source's styling.
    ///
    /// The pasteboard is injected (`htmlForPaste`, `plainTextForPaste`) because
    /// `UIPasteboard.general` hangs this bundle (GitHub issue #40).
    @MainActor
    struct RichPasteTests {
        private final class Box { var value = AttributedString() }

        private struct Harness {
            let textView: RichTextTextView
            /// Held here because `UITextView.delegate` is weak.
            let coordinator: Coordinator
            let model: RichTextEditorModel
            let box: Box
            let window: UIWindow
        }

        private func harness(
            _ html: String,
            caret: Int,
            pasteboardHTML: String?,
            pasteboardText: String? = nil
        ) -> Harness {
            let box = Box()
            box.value = RichTextHTML.decode(html)
            let binding = Binding<AttributedString>(get: { box.value }, set: { box.value = $0 })
            let model = RichTextEditorModel()
            let textView = RichTextTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
            let window = UIWindow(frame: textView.frame)
            window.addSubview(textView)
            window.makeKeyAndVisible()
            textView.htmlForPaste = { pasteboardHTML }
            textView.plainTextForPaste = { pasteboardText }
            let coordinator = Coordinator(text: binding, model: model)
            let engine = UIKitEditorEngine(textView: textView)
            engine.text = box.value
            textView.engine = engine
            textView.delegate = coordinator
            coordinator.attach(engine: engine)
            model.attach(engine)
            textView.selectedRange = NSRange(location: caret, length: 0)
            coordinator.textViewDidChangeSelection(textView)
            return Harness(textView: textView, coordinator: coordinator, model: model, box: box, window: window)
        }

        private func font(at offset: Int, _ textView: UITextView) -> UIFont? {
            textView.textStorage.attribute(.font, at: offset, effectiveRange: nil) as? UIFont
        }

        // MARK: - Pasting HTML

        @Test func pastedBoldStaysBoldInTheDocument() {
            let h = harness("<p>ab</p>", caret: 1, pasteboardHTML: "<p><b>XY</b></p>")
            h.textView.paste(nil)

            #expect(RichTextHTML.encode(h.model.text) == "<p>a<b>XY</b>b</p>")
            // Published to the binding without anyone calling the delegate by hand.
            #expect(h.box.value == h.model.text)
        }

        @Test func theUndoStepIsNamedPaste() {
            // UIKit builds "Undo Paste" for the shake-to-undo alert and the
            // keyboard's undo button from this name.
            let h = harness("<p>ab</p>", caret: 1, pasteboardHTML: "<p><b>XY</b></p>")
            h.textView.paste(nil)

            #expect(h.textView.undoManager?.undoActionName == "Paste")
        }

        @Test func pastedTextIsDrawnInTheTheme() {
            let h = harness("<p>ab</p>", caret: 1, pasteboardHTML: "<p><b>XY</b></p>")
            h.textView.paste(nil)

            let pasted = font(at: 1, h.textView)
            #expect(pasted?.fontDescriptor.symbolicTraits.contains(.traitBold) == true)
            #expect(pasted?.pointSize == font(at: 0, h.textView)?.pointSize)
        }

        @Test func aWordStyleDocumentPastesItsBlocks() {
            // Word and Outlook put a whole document on the pasteboard, head and
            // all; the decoder already skips everything that isn't content.
            let html = """
            <html><head><style>p { color: red; }</style></head>
            <body><h1>Title</h1><p>Body <i>text</i></p></body></html>
            """
            let h = harness("<p></p>", caret: 0, pasteboardHTML: html)
            h.textView.paste(nil)

            #expect(RichTextHTML.encode(h.model.text) == "<h1>Title</h1>\n<p>Body <i>text</i></p>")
        }

        // MARK: - Falling back

        @Test func withoutHTMLThePlainTextIsTypedIn() {
            let h = harness("<h2>ab</h2>", caret: 1, pasteboardHTML: nil, pasteboardText: "XY")
            h.textView.paste(nil)

            #expect(RichTextHTML.encode(h.model.text) == "<h2>aXYb</h2>")
            #expect(h.box.value == h.model.text)
        }

        @Test func htmlWithNoTextFallsBackToThePlainText() {
            let h = harness("<p>ab</p>", caret: 1, pasteboardHTML: "<img src=\"x.png\">", pasteboardText: "XY")
            h.textView.paste(nil)

            #expect(RichTextHTML.encode(h.model.text) == "<p>aXYb</p>")
        }

        // MARK: - The rule

        @Test func theRuleOutsidePlainTextMode() {
            func rule(isEditable: Bool = true, html: String?, text: String?) -> RichTextTextView.PasteDisposition {
                RichTextTextView.disposition(
                    pasteAsPlainText: false,
                    isEditable: isEditable,
                    html: { html },
                    plainText: { text }
                )
            }
            #expect(rule(html: "<p><b>A</b></p>", text: "A") == .insertRich(RichTextHTML.decode("<p><b>A</b></p>")))
            #expect(rule(html: nil, text: "a\r\nb") == .insert("a\nb"))
            #expect(rule(html: "<img src=\"x.png\">", text: "A") == .insert("A"))
            // Nothing textual at all (an image): UIKit's own paste, as before.
            #expect(rule(html: nil, text: nil) == .system)
            #expect(rule(isEditable: false, html: "<p>A</p>", text: "A") == .nothing)
        }

        @Test func thePlainTextIsReadOnlyWhenTheHTMLIsUnusable() {
            var reads = 0
            _ = RichTextTextView.disposition(
                pasteAsPlainText: false,
                isEditable: true,
                html: { "<p>A</p>" },
                plainText: { reads += 1; return "A" }
            )
            #expect(reads == 0)
        }

        @Test func plainTextModeNeverReadsTheHTML() {
            var reads = 0
            let disposition = RichTextTextView.disposition(
                pasteAsPlainText: true,
                isEditable: true,
                html: { reads += 1; return "<p><b>A</b></p>" },
                plainText: { "A" }
            )
            #expect(disposition == .insert("A"))
            #expect(reads == 0)
        }
    }
#endif
