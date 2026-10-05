// DocumentReplacementTests.swift
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

    /// Replacing the document wholesale — what the example app does when you
    /// switch samples, and what any consumer does when a `Binding` changes.
    ///
    /// This crashed in the app: mutating `textStorage` directly leaves
    /// `UITextView`'s text-input machinery holding a stale document snapshot, and
    /// the next selection change made its tokenizer read past the end
    /// (`NSRangeException`, `{9, 109}` against a 109-length string). The engine now
    /// brackets the mutation with the `UITextInputDelegate` notifications and
    /// commits the storage transaction before touching the selection.
    @MainActor
    struct DocumentReplacementTests {
        /// Records what UIKit's text-input machinery would have been told.
        private final class RecordingInputDelegate: NSObject, UITextInputDelegate {
            var textWillChangeCount = 0
            var textDidChangeCount = 0
            var selectionWillChangeCount = 0
            var selectionDidChangeCount = 0

            func selectionWillChange(_: (any UITextInput)?) {
                selectionWillChangeCount += 1
            }

            func selectionDidChange(_: (any UITextInput)?) {
                selectionDidChangeCount += 1
            }

            func textWillChange(_: (any UITextInput)?) {
                textWillChangeCount += 1
            }

            func textDidChange(_: (any UITextInput)?) {
                textDidChangeCount += 1
            }

            /// Required on iOS 18.4+; the package's floor is iOS 17, so it is
            /// availability-gated rather than unconditional.
            @available(iOS 18.4, *)
            func conversationContext(_: UIConversationContext?, didChange _: (any UITextInput)?) {}
        }

        private func editor() -> (UITextView, UIKitEditorEngine, UIWindow) {
            let textView = UITextView(frame: CGRect(x: 0, y: 0, width: 393, height: 400))
            let window = UIWindow(frame: textView.frame)
            window.addSubview(textView)
            window.makeKeyAndVisible()
            return (textView, UIKitEditorEngine(textView: textView), window)
        }

        private let long = "<h1>Heading</h1><ul><li>first bullet</li><li>second bullet — keep typing here until this item wraps onto a second line</li></ul><p>a paragraph after the list</p>"
        private var short: String {
            "<p>Ordered list past ten:</p><ol>" + (1 ... 12).map { "<li>item \($0)</li>" }.joined() + "</ol>"
        }

        @Test func switchingToAShorterDocumentLeavesAValidSelection() {
            let (textView, engine, window) = editor()
            engine.text = RichTextHTML.decode(long)
            engine.selection = TextSelection(location: 9, length: 100)

            engine.text = RichTextHTML.decode(short)

            let selection = textView.selectedRange
            #expect(selection.location + selection.length <= textView.textStorage.length)
            // A range from the old document is meaningless in the new one.
            #expect(selection.length == 0)
            _ = window
        }

        @Test func aReplacementTellsTheTextInputMachineryTheTextChanged() {
            let (textView, engine, window) = editor()
            engine.text = RichTextHTML.decode(long)
            let delegate = RecordingInputDelegate()
            textView.inputDelegate = delegate

            engine.text = RichTextHTML.decode(short)

            #expect(delegate.textWillChangeCount == 1)
            #expect(delegate.textDidChangeCount == 1)
            #expect(delegate.selectionWillChangeCount == 1)
            #expect(delegate.selectionDidChangeCount == 1)
            _ = window
        }

        @Test func anAttributeOnlyRenderDoesNotClaimTheTextChanged() {
            // A formatting command leaves the characters alone, so telling UIKit
            // the text changed would be a lie — and would cost it a resync.
            let (textView, engine, window) = editor()
            engine.text = RichTextHTML.decode("<p>hello</p>")
            engine.selection = TextSelection(location: 0, length: 5)
            let delegate = RecordingInputDelegate()
            textView.inputDelegate = delegate

            engine.apply(.toggleBold)

            #expect(delegate.textWillChangeCount == 0)
            #expect(delegate.textDidChangeCount == 0)
            // A range selection survives an attributes-only render.
            #expect(textView.selectedRange == NSRange(location: 0, length: 5))
            _ = window
        }

        @Test func repeatedlySwitchingBetweenDocumentsStaysConsistent() {
            let (textView, engine, window) = editor()
            for _ in 0 ..< 5 {
                engine.text = RichTextHTML.decode(long)
                engine.selection = TextSelection(location: 5, length: 50)
                engine.text = RichTextHTML.decode(short)
                #expect(textView.textStorage.length == 109)
                engine.selection = TextSelection(location: 100, length: 9)
            }
            #expect(RichTextHTML.encode(engine.text).hasPrefix("<p>Ordered list past ten:</p>"))
            _ = window
        }
    }
#endif
