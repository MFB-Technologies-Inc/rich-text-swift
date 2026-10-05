// StuckBlackColorRegressionTests.swift
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

    /// Blocker 1, end to end: before the fix, a consumer binding
    /// `RichTextEditor(text:)` to a document that already contained an explicit
    /// black run put black straight into `model.formatState.textColor` (the
    /// encoder would then silently drop it, and `RichTextControl.textColor.isActive(in:)`
    /// would report the control active for a color that could never be
    /// serialized). Worse, the user could not remove it: `TextColorControl`'s drag
    /// guard compares a freshly picked color against `model.formatState.textColor`,
    /// and picking black again is equal to the black already "in" the document,
    /// so the guard silently no-ops.
    ///
    /// With normalization applied at the engine's `text` setter (the seam
    /// `RichTextEditorModel.setText(_:)` goes through), black can never actually
    /// reach `formatState` in the first place, so the trap can't occur:
    /// `formatState.textColor` reads `nil` immediately after the document is set,
    /// and picking black from there is a genuine (nil -> nil, effectively)
    /// no-op — never a stuck non-removable color.
    @MainActor
    struct StuckBlackColorRegressionTests {
        private func harness() -> (UITextView, RichTextEditorModel) {
            let model = RichTextEditorModel()
            let textView = UITextView()
            let engine = UIKitEditorEngine(textView: textView)
            model.attach(engine)
            return (textView, model)
        }

        @Test func aDocumentWithAnExplicitBlackRunNeverReachesFormatStateAsBlack() async {
            let (_, model) = harness()

            var doc = AttributedString("hi")
            doc.blockStyle = .paragraph
            doc.textColor = RichTextColor.black
            model.setText(doc)
            await settle()

            #expect(model.formatState.textColor == nil)
        }

        @Test func pickingBlackAfterSettingABlackDocumentEndsWithNoColorRatherThanStickingSilently() async {
            let (textView, model) = harness()

            var doc = AttributedString("hi")
            doc.blockStyle = .paragraph
            doc.textColor = RichTextColor.black
            model.setText(doc)
            await settle()

            textView.selectedRange = NSRange(location: 0, length: 2)
            model.synchronizeSelection()
            await settle()

            let menu = TextColorControl(model: model, isActive: false)
            // The user picks black in the control -- the only way `ColorPicker`
            // can express "remove the color", since it can't bind an optional.
            menu.selection.wrappedValue = Color(RichTextColor.black)
            await settle()

            #expect(model.formatState.textColor == nil)
            #expect(RichTextHTML.encode(model.text) == "<p>hi</p>")
        }
    }
#endif
