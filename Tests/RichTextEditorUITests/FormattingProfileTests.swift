// FormattingProfileTests.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
import RichTextCore
@testable import RichTextEditorUI
import RichTextEngine
import Testing

/// The UI half of `RichTextFormatting`: which formatting each toolbar control
/// needs, the toolbar's filter, and the model handing the profile to its
/// engine. The engine's enforcement is `UIKitEditorEngineFormattingProfileTests`.
@MainActor
struct FormattingProfileTests {
    @Test func eachControlNeedsItsFormatting() {
        let cases: [(RichTextControl, RichTextFormatting)] = [
            (.bold, .bold), (.italic, .italic), (.underline, .underline),
            (.strikethrough, .strikethrough), (.textColor, .textColor),
            (.unorderedList, .bulletedLists), (.orderedList, .numberedLists),
            (.heading(.h1), .headings), (.heading(.h3), .headings),
        ]
        for (control, formatting) in cases {
            #expect(control.formatting == formatting)
        }
    }

    @Test func theToolbarShowsOnlyAllowedControlsInTheirOrder() {
        #expect(RichTextControl.visible([RichTextControl].html, allowing: .markdown) == [RichTextControl].markdown)
        #expect(RichTextControl.visible([RichTextControl].html, allowing: .all) == [RichTextControl].html)
    }

    @Test func theModelAllowsEverythingByDefault() {
        #expect(RichTextEditorModel().allowedFormatting == .all)
    }

    @Test func theModelHandsItsProfileToAnEngineAttachedLater() {
        let model = RichTextEditorModel()
        model.setAllowedFormatting(.markdown)
        let engine = FakeEditorEngine()

        model.attach(engine)

        #expect(engine.allowedFormatting == .markdown)
    }

    @Test func theModelForwardsAProfileChangeToItsEngine() {
        let model = RichTextEditorModel()
        let engine = FakeEditorEngine()
        model.attach(engine)

        model.setAllowedFormatting(.markdown)

        #expect(model.allowedFormatting == .markdown)
        #expect(engine.allowedFormatting == .markdown)
    }
}
