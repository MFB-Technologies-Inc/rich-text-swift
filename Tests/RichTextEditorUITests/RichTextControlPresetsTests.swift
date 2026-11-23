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
            case .heading, .paragraphStyleAndColor: true
            default: false
            }
        }
        #expect(hasHeading == false)
    }

    @Test func htmlIsInlineAndListControlsThenTheParagraphStyleAndColorPanel() {
        #expect([RichTextControl].html == [
            .bold, .italic, .underline, .strikethrough,
            .unorderedList, .orderedList, .paragraphStyleAndColor,
        ])
    }

    @Test func markdownIsHtmlWithoutUnderlineInTheSameOrder() {
        #expect([RichTextControl].markdown == [RichTextControl].html.filter { $0 != .underline })
    }

    @Test func noPresetContainsDuplicates() {
        for preset in [[RichTextControl].default, .html, .markdown] {
            #expect(Set(preset).count == preset.count)
        }
    }

    @Test func everyControlInHtmlHasADistinctAccessibilityLabel() {
        let labels = [RichTextControl].html.map(\.accessibilityLabel)
        #expect(Set(labels).count == labels.count)
    }

    @Test func everyControlInMarkdownHasADistinctAccessibilityLabel() {
        let labels = [RichTextControl].markdown.map(\.accessibilityLabel)
        #expect(Set(labels).count == labels.count)
    }
}
