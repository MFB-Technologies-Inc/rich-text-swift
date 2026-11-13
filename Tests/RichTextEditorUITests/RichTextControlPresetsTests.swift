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
            case .heading, .headings: true
            default: false
            }
        }
        #expect(hasHeading == false)
    }

    @Test func htmlStartsWithDefaultAndAddsOneHeadingMenu() {
        let html = [RichTextControl].html
        let defaults = [RichTextControl].default
        #expect(Array(html.prefix(defaults.count)) == defaults)
        #expect(Array(html.dropFirst(defaults.count)) == [.headings])
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
