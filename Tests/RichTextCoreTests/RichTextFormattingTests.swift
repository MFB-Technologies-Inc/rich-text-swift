// RichTextFormattingTests.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
@testable import RichTextCore
import Testing

struct RichTextFormattingTests {
    private let everyOption: [RichTextFormatting] = [
        .bold, .italic, .underline, .strikethrough, .textColor,
        .headings, .bulletedLists, .numberedLists, .blockquotes,
    ]

    @Test func allHoldsEveryOption() {
        for option in everyOption {
            #expect(RichTextFormatting.all.contains(option))
        }
    }

    @Test func htmlAllowsEverythingTheModelHoldsToday() {
        #expect(RichTextFormatting.html == .all)
    }

    @Test func markdownIsAllWithoutUnderlineAndTextColor() {
        #expect(RichTextFormatting.markdown == RichTextFormatting.all.subtracting([.underline, .textColor]))
    }

    @Test func paragraphsAreAlwaysAllowed() {
        #expect(RichTextFormatting().allows(.paragraph))
    }

    @Test func eachBlockRoleNeedsItsOption() {
        let cases: [(BlockStyle, RichTextFormatting)] = [
            (.heading(1), .headings),
            (.heading(3), .headings),
            (.listItem(.unordered, depth: 2), .bulletedLists),
            (.listItem(.ordered, depth: 0), .numberedLists),
            (.blockquote, .blockquotes),
        ]
        for (style, option) in cases {
            #expect(option.allows(style))
            #expect(!RichTextFormatting.all.subtracting(option).allows(style))
        }
    }
}
