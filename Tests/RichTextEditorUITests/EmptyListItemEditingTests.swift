// EmptyListItemEditingTests.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
import RichTextCore
import Testing

#if os(iOS)
    @testable import RichTextEngine
    import UIKit

    /// Deleting a middle list item's text leaves an empty item that keeps its
    /// number and saves as one; one more backspace removes the row.
    @MainActor
    struct EmptyListItemEditingTests {
        private func emptiedMiddleItem() -> (UITextView, UIKitEditorEngine, UIWindow) {
            let textView = UITextView(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
            let window = UIWindow(frame: textView.frame)
            window.addSubview(textView)
            window.makeKeyAndVisible()
            let engine = UIKitEditorEngine(textView: textView)
            engine.text = RichTextHTML.decode("<ol><li>a</li><li>b</li><li>c</li></ol>")
            // "a" is 0..<1, "b" 2..<3, "c" 4..<5. Delete "b".
            engine.selection = TextSelection(location: 2, length: 1)
            textView.deleteBackward()
            engine.synchronizeFromTextView()
            return (textView, engine, window)
        }

        @Test func anEmptiedMiddleItemKeepsItsNumberAndSavesAsAnItem() {
            let (_, engine, window) = emptiedMiddleItem()
            // Move the caret away, so no pending style is involved.
            engine.selection = .caret(at: 0)
            #expect(engine.listMarkers.marker(atUTF16Offset: 2) == "2.")
            #expect(engine.listMarkers.marker(atUTF16Offset: 3) == "3.")
            #expect(RichTextHTML.encode(engine.text) == "<ol><li>a</li><li></li><li>c</li></ol>")
            _ = window
        }

        @Test func oneMoreBackspaceRemovesTheRow() {
            let (textView, engine, window) = emptiedMiddleItem()
            textView.deleteBackward()
            engine.synchronizeFromTextView()
            #expect(RichTextHTML.encode(engine.text) == "<ol><li>a</li><li>c</li></ol>")
            #expect(engine.listMarkers.marker(atUTF16Offset: 2) == "2.")
            _ = window
        }
    }
#endif
