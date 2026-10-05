// PlainTextPasteTests.swift
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

    /// `pasteAsPlainText` addresses a rich-paste discrepancy.
    /// A rich paste leaves the pasteboard's own fonts and colors in `textStorage`
    /// while the semantic read-back drops them, so what the user sees is not what
    /// gets saved. Consumers whose users paste from Word and Outlook can opt out
    /// of that entirely.
    ///
    /// Everything here asserts on the **document** (GitHub issue #25:
    /// SwiftUI accessibility labels are unreachable from a hosted `UIView` tree),
    /// plus — for the cases where the whole point is whether the view and the
    /// document agree — on the text view's own storage.
    ///
    /// The styled content arrives as an `NSAttributedString` written straight into
    /// `textStorage` rather than via `UIPasteboard`, because
    /// `UIPasteboard.general` is unusable from this bundle: with no host app the
    /// first access blocks the main thread forever and hangs every test in the
    /// bundle. See `RichTextTextView.plainTextForPaste`.
    @MainActor
    struct PlainTextPasteTests {
        private final class Box { var value = AttributedString() }

        private struct Harness {
            let textView: RichTextTextView
            let coordinator: Coordinator
            let model: RichTextEditorModel
            let box: Box
        }

        private func harness(
            _ html: String,
            pasteAsPlainText: Bool = true,
            isEditable: Bool = true,
            pasteboardText: String? = nil
        ) -> Harness {
            let box = Box()
            box.value = RichTextHTML.decode(html)
            let binding = Binding<AttributedString>(get: { box.value }, set: { box.value = $0 })
            let model = RichTextEditorModel()
            let textView = RichTextTextView()
            textView.pasteAsPlainText = pasteAsPlainText
            textView.plainTextForPaste = { pasteboardText }
            let coordinator = Coordinator(text: binding, model: model)
            let engine = UIKitEditorEngine(textView: textView)
            engine.text = box.value
            textView.isEditable = isEditable
            model.setEditable(isEditable)
            textView.delegate = coordinator
            coordinator.attach(engine: engine)
            model.attach(engine)
            return Harness(textView: textView, coordinator: coordinator, model: model, box: box)
        }

        /// 36pt bold red underlined content — the shape a Word or Outlook paste
        /// actually carries.
        private func styled(_ string: String) -> NSAttributedString {
            var attributed = AttributedString(string)
            attributed.font = .systemFont(ofSize: 36, weight: .bold)
            attributed.foregroundColor = UIColor.red
            attributed.underlineStyle = .single
            return NSAttributedString(attributed)
        }

        private func containsPasteboardStyling(_ storage: NSTextStorage) -> Bool {
            var found = false
            let full = NSRange(location: 0, length: storage.length)
            storage.enumerateAttribute(.font, in: full) { value, _, _ in
                if (value as? UIFont)?.pointSize == 36 {
                    found = true
                }
            }
            storage.enumerateAttribute(.foregroundColor, in: full) { value, _, _ in
                if value as? UIColor == UIColor.red {
                    found = true
                }
            }
            return found
        }

        // MARK: - The defect the option mitigates

        /// Characterizes the rich-paste discrepancy so the
        /// contrast below is real rather than asserted: a rich paste — which is `textStorage`
        /// taking the pasteboard's own attributed string — leaves the view showing 36pt red
        /// text that the saved document knows nothing about.
        @Test func aRichPasteLeavesTheViewAndTheDocumentDisagreeing() {
            let h = harness("<p>a</p>", pasteAsPlainText: false)
            h.textView.textStorage.replaceCharacters(in: NSRange(location: 1, length: 0), with: styled("Pasted"))
            h.coordinator.textViewDidChange(h.textView)

            #expect(containsPasteboardStyling(h.textView.textStorage))
            // ...while the document that would be saved has none of it.
            #expect(RichTextHTML.encode(h.model.text) == "<p>aPasted</p>")
        }

        // MARK: - The option

        /// The core guarantee: with the option on, pasted content lands as plain
        /// text — in the document *and* on screen.
        @Test func aPlainTextPasteLeavesNoPasteboardAttributes() {
            let h = harness("<p>a</p>", pasteboardText: String(styled("Pasted").string))
            h.textView.selectedRange = NSRange(location: 1, length: 0)
            h.coordinator.textViewDidChangeSelection(h.textView)

            h.textView.paste(nil)
            h.coordinator.textViewDidChange(h.textView)

            #expect(String(h.model.text.characters) == "aPasted")
            #expect(RichTextHTML.encode(h.model.text) == "<p>aPasted</p>")
            for run in h.model.text.runs {
                #expect(run.bold != true)
                #expect(run.italic != true)
                #expect(run.underline != true)
                #expect(run.strikethrough != true)
                #expect(run.textColor == nil)
            }
            // And the view agrees with the document — the WYSIWYG half of the discrepancy.
            #expect(!containsPasteboardStyling(h.textView.textStorage))
        }

        /// A multi-line paste has to produce whole blocks, not a corrupt marker:
        /// each line becomes its own block carrying the caret block's role.
        @Test func aMultiLinePlainPasteProducesOneBlockPerLine() {
            let h = harness("<p></p>", pasteboardText: "one\ntwo\nthree")
            h.textView.selectedRange = NSRange(location: 0, length: 0)
            h.coordinator.textViewDidChangeSelection(h.textView)

            h.textView.paste(nil)
            h.coordinator.textViewDidChange(h.textView)

            #expect(RichTextHTML.encode(h.model.text) == "<p>one</p>\n<p>two</p>\n<p>three</p>")
            #expect(BlockScanner.blocks(of: h.model.text).map(\.style) == [.paragraph, .paragraph, .paragraph])
        }

        /// Pasting inside a list keeps the caret block's role on every pasted
        /// line, because the role rides in the text view's typing attributes.
        @Test func aMultiLinePlainPasteInsideAListStaysInTheList() {
            let h = harness("<ul><li>one</li></ul>", pasteboardText: "\ntwo")
            h.textView.selectedRange = NSRange(location: 3, length: 0)
            h.coordinator.textViewDidChangeSelection(h.textView)

            h.textView.paste(nil)
            h.coordinator.textViewDidChange(h.textView)

            #expect(RichTextHTML.encode(h.model.text) == "<ul><li>one</li><li>two</li></ul>")
        }

        /// Same rule with the caret in a heading: pasted lines take the CARET
        /// BLOCK'S role (GitHub issue #5), not `.paragraph` — routing each line
        /// through `model.insertNewline()` for proper Return-policy continuation
        /// would make an N-line paste O(N²). This pins that documented, deliberate
        /// behavior for `.heading`, which the task's own motivating example
        /// (headline text) uses, but which had no direct coverage.
        @Test func aMultiLinePlainPasteInsideAHeadingStaysInTheHeading() {
            let h = harness("<h1>one</h1>", pasteboardText: "\ntwo\nthree")
            h.textView.selectedRange = NSRange(location: 3, length: 0)
            h.coordinator.textViewDidChangeSelection(h.textView)

            h.textView.paste(nil)
            h.coordinator.textViewDidChange(h.textView)

            #expect(RichTextHTML.encode(h.model.text) == "<h1>one</h1>\n<h1>two</h1>\n<h1>three</h1>")
            #expect(BlockScanner.blocks(of: h.model.text).map(\.style)
                == [.heading(1), .heading(1), .heading(1)])
        }

        /// Same rule again with the caret in a `.blockquote` — pinning the same
        /// documented behavior (GitHub issue #5) for the newly added quote role.
        @Test func aMultiLinePlainPasteInsideABlockquoteStaysInTheBlockquote() {
            let h = harness("<blockquote>one</blockquote>", pasteboardText: "\ntwo\nthree")
            h.textView.selectedRange = NSRange(location: 3, length: 0)
            h.coordinator.textViewDidChangeSelection(h.textView)

            h.textView.paste(nil)
            h.coordinator.textViewDidChange(h.textView)

            #expect(RichTextHTML.encode(h.model.text)
                == "<blockquote>one</blockquote>\n<blockquote>two</blockquote>\n<blockquote>three</blockquote>")
            #expect(BlockScanner.blocks(of: h.model.text).map(\.style)
                == [.blockquote, .blockquote, .blockquote])
        }

        /// Windows line endings are what a Word or Outlook paste actually
        /// carries. They must become block separators, not a stray `\r` inside a
        /// block.
        @Test func windowsLineEndingsBecomeBlockSeparators() {
            let h = harness("<p></p>", pasteboardText: "one\r\ntwo\rthree")
            h.textView.selectedRange = NSRange(location: 0, length: 0)
            h.coordinator.textViewDidChangeSelection(h.textView)

            h.textView.paste(nil)
            h.coordinator.textViewDidChange(h.textView)

            #expect(!String(h.model.text.characters).unicodeScalars.contains("\r"))
            #expect(RichTextHTML.encode(h.model.text) == "<p>one</p>\n<p>two</p>\n<p>three</p>")
        }

        @Test(arguments: [
            ("one\r\ntwo", "one\ntwo"),
            ("one\rtwo", "one\ntwo"),
            ("one\ntwo", "one\ntwo"),
            ("\r\n", "\n"),
            ("plain", "plain"),
            ("one\u{2029}two", "one\ntwo"),
            ("one\u{2028}two", "one\u{2028}two"),
        ])
        func lineEndingNormalization(input: String, expected: String) {
            #expect(RichTextTextView.normalizingLineEndings(input) == expected)
        }

        /// Inline formatting the *user* set stays on: a plain-text paste strips
        /// the pasteboard's styling, it does not reset the caret's own state.
        @Test func aPlainPasteAdoptsTheCaretsOwnTypingAttributes() {
            let h = harness("<p><b>bold</b></p>", pasteboardText: "more")
            h.textView.selectedRange = NSRange(location: 4, length: 0)
            h.coordinator.textViewDidChangeSelection(h.textView)

            h.textView.paste(nil)
            h.coordinator.textViewDidChange(h.textView)

            #expect(RichTextHTML.encode(h.model.text) == "<p><b>boldmore</b></p>")
        }

        /// A pasteboard holding no text inserts nothing — no `super.paste`
        /// fallback, which would reintroduce exactly the styled content the
        /// option exists to keep out.
        @Test func aPasteboardWithNoTextInsertsNothing() {
            let h = harness("<p>a</p>", pasteboardText: nil)
            h.textView.selectedRange = NSRange(location: 1, length: 0)
            h.coordinator.textViewDidChangeSelection(h.textView)

            h.textView.paste(nil)
            h.coordinator.textViewDidChange(h.textView)

            #expect(RichTextHTML.encode(h.model.text) == "<p>a</p>")
            #expect(h.textView.textStorage.string == "a")
        }

        /// A read-only editor takes no paste, whatever route it arrives by — the
        /// same rule the model applies to commands.
        @Test func aReadOnlyEditorTakesNoPlainTextPaste() {
            let h = harness("<p>a</p>", isEditable: false, pasteboardText: "Pasted")
            h.textView.selectedRange = NSRange(location: 1, length: 0)

            h.textView.paste(nil)
            h.coordinator.textViewDidChange(h.textView)

            #expect(RichTextHTML.encode(h.model.text) == "<p>a</p>")
            #expect(h.textView.textStorage.string == "a")
        }

        // MARK: - The rule itself

        @Test func theRuleCoversEveryCase() {
            #expect(RichTextTextView.disposition(
                pasteAsPlainText: true, isEditable: true, html: { "<p><b>ignored</b></p>" }, plainText: { "Pasted" }
            ) == .insert("Pasted"))
            #expect(RichTextTextView.disposition(
                pasteAsPlainText: true, isEditable: false, html: { "<p><b>ignored</b></p>" }, plainText: { "Pasted" }
            ) == .nothing)
            #expect(RichTextTextView.disposition(
                pasteAsPlainText: true, isEditable: true, html: { "<p><b>ignored</b></p>" }, plainText: { nil }
            ) == .nothing)
            #expect(RichTextTextView.disposition(
                pasteAsPlainText: true, isEditable: true, html: { "<p><b>ignored</b></p>" }, plainText: { "" }
            ) == .nothing)
            #expect(RichTextTextView.disposition(
                pasteAsPlainText: true, isEditable: true, html: { "<p><b>ignored</b></p>" }, plainText: { "a\r\nb" }
            ) == .insert("a\nb"))
        }

        // MARK: - Threading the option through the public entry point

        private func hostedTextView(pasteAsPlainText: Bool?) async -> RichTextTextView? {
            let root: AnyView = if let pasteAsPlainText {
                .init(RichTextEditor(
                    text: .constant(RichTextHTML.decode("<p>hello</p>")),
                    pasteAsPlainText: pasteAsPlainText
                ))
            } else {
                .init(RichTextEditor(text: .constant(RichTextHTML.decode("<p>hello</p>"))))
            }
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
            window.rootViewController = UIHostingController(rootView: root)
            window.makeKeyAndVisible()
            window.layoutIfNeeded()
            await settle()
            func find(_ view: UIView) -> RichTextTextView? {
                if let found = view as? RichTextTextView {
                    return found
                }
                for subview in view.subviews {
                    if let found = find(subview) {
                        return found
                    }
                }
                return nil
            }
            return find(window.rootViewController!.view)
        }

        /// The public entry point defaults to off, so no existing call site
        /// changes behavior.
        @Test func theEditorDefaultsToRichPaste() async {
            let textView = await hostedTextView(pasteAsPlainText: nil)
            #expect(textView != nil)
            #expect(textView?.pasteAsPlainText == false)
        }

        @Test func theEditorForwardsThePlainTextPasteOption() async {
            let textView = await hostedTextView(pasteAsPlainText: true)
            #expect(textView?.pasteAsPlainText == true)
        }
    }
#endif
