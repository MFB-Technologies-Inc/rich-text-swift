// FormattingProfileHostingTests.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
import RichTextCore
import Testing

#if os(iOS)
    @testable import RichTextEditorUI
    import SwiftUI
    import UIKit

    /// `RichTextEditor(text:allowedFormatting:)` in a real hierarchy: the
    /// bound document is stripped, the toolbar hides what the profile
    /// excludes even when given a wider preset, and the text view offers no
    /// formatting shortcuts that could bypass it. Simulator-only.
    @MainActor
    struct FormattingProfileHostingTests {
        private func hosted(_ document: AttributedString) async -> (UIWindow, RichTextEditorModel) {
            let model = RichTextEditorModel()
            let root = RichTextEditor(text: .constant(document), allowedFormatting: .markdown)
                .richTextToolbar(.html, model: model)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
            window.rootViewController = UIHostingController(rootView: root)
            window.makeKeyAndVisible()
            window.layoutIfNeeded()
            await settle()
            window.layoutIfNeeded()
            await settle()
            return (window, model)
        }

        @Test func theEditorHandsItsProfileToTheModel() async {
            let (_, model) = await hosted(RichTextHTML.decode("<p>hello</p>"))
            #expect(model.allowedFormatting == .markdown)
        }

        @Test func aBoundDocumentLosesDisallowedFormatting() async {
            let (_, model) = await hosted(RichTextHTML.decode("<p><b>a</b><u>b</u></p>"))
            #expect(String(model.text.characters) == "ab")
            #expect(!model.text.runs.contains { $0.underline == true })
            #expect(model.text.runs.first?.bold == true)
        }

        @Test func theToolbarHidesDisallowedControls() async {
            let (_, model) = await hosted(RichTextHTML.decode("<p>hello</p>"))
            let toolbar = RichTextToolbar(controls: .html, model: model)
            #expect(toolbar.visibleControls == [RichTextControl].markdown)
        }

        /// ⌘B, ⌘I and ⌘U come from `allowsEditingTextAttributes`; with it off
        /// the text view offers no formatting that skips the profile.
        @Test func theTextViewOffersNoFormattingShortcuts() {
            #expect(RichTextTextView().allowsEditingTextAttributes == false)
        }
    }
#endif
