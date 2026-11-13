// RichTextControlPresetsTests.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
@testable import RichTextEditorUI
import Testing

struct RichTextControlPresetsTests {
    @Test func defaultIsExactlyTheSevenInlineAndListControlsInOrder() {
        #expect([RichTextControl].default == [
            .bold, .italic, .underline, .strikethrough,
            .textColor, .unorderedList, .orderedList,
        ])
    }

    @Test func defaultContainsNoHeadingControl() {
        let hasHeading = [RichTextControl].default.contains { control in
            switch control {
            case .heading, .format: true
            default: false
            }
        }
        #expect(hasHeading == false)
    }

    @Test func htmlIsInlineAndListControlsThenTheFormatPanel() {
        #expect([RichTextControl].html == [
            .bold, .italic, .underline, .strikethrough,
            .unorderedList, .orderedList, .format,
        ])
    }

    @Test func neitherPresetContainsDuplicates() {
        #expect(Set([RichTextControl].default).count == [RichTextControl].default.count)
        #expect(Set([RichTextControl].html).count == [RichTextControl].html.count)
    }

    @Test func everyControlInHtmlHasADistinctAccessibilityLabel() {
        let labels = [RichTextControl].html.map(\.accessibilityLabel)
        #expect(Set(labels).count == labels.count)
    }
}
