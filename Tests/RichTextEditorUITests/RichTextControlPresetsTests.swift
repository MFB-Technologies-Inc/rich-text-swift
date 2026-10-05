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
            if case .heading = control {
                return true
            }
            return false
        }
        #expect(hasHeading == false)
    }

    @Test func htmlStartsWithDefaultAndAddsExactlyTheThreeHeadingLevels() {
        let html = [RichTextControl].html
        let defaults = [RichTextControl].default
        #expect(Array(html.prefix(defaults.count)) == defaults)
        #expect(Array(html.dropFirst(defaults.count)) == [
            .heading(.h1), .heading(.h2), .heading(.h3),
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
