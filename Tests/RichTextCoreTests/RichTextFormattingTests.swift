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

    /// Pinned member by member, so an option added to `all` later has to be
    /// added to each format's profile on purpose.
    @Test func htmlHoldsExactlyWhatHTMLCanSave() {
        #expect(RichTextFormatting.html == [
            .bold, .italic, .underline, .strikethrough, .textColor,
            .headings, .bulletedLists, .numberedLists, .blockquotes,
        ])
    }

    @Test func markdownHoldsExactlyWhatMarkdownCanSave() {
        #expect(RichTextFormatting.markdown == [
            .bold, .italic, .strikethrough,
            .headings, .bulletedLists, .numberedLists, .blockquotes,
        ])
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
