// RichTextFormatting.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation

/// The formatting an editor allows: a profile it keeps every document to.
///
/// Formatting outside the profile never reaches the document, however it
/// arrives. The toolbar hides its controls, commands for it do nothing, and
/// paste, drag and drop, and the text binding strip it on the way in. Text is
/// always kept: a disallowed heading, list item or quote becomes a paragraph,
/// and a disallowed inline mark or color is removed.
///
/// Pick the profile of the format you save to, so what the user sees is what
/// gets saved:
///
/// ```swift
/// RichTextEditor(text: $document, allowedFormatting: .markdown)
///     .richTextToolbar(.markdown)
/// ```
public struct RichTextFormatting: OptionSet, Hashable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let bold = RichTextFormatting(rawValue: 1 << 0)
    public static let italic = RichTextFormatting(rawValue: 1 << 1)
    public static let underline = RichTextFormatting(rawValue: 1 << 2)
    public static let strikethrough = RichTextFormatting(rawValue: 1 << 3)
    public static let textColor = RichTextFormatting(rawValue: 1 << 4)
    /// Headings at every level the model holds.
    public static let headings = RichTextFormatting(rawValue: 1 << 5)
    public static let bulletedLists = RichTextFormatting(rawValue: 1 << 6)
    public static let numberedLists = RichTextFormatting(rawValue: 1 << 7)
    public static let blockquotes = RichTextFormatting(rawValue: 1 << 8)

    /// Everything the editor supports. The default, so an editor that names
    /// no profile behaves as it always has.
    public static let all: RichTextFormatting = [
        .bold, .italic, .underline, .strikethrough, .textColor,
        .headings, .bulletedLists, .numberedLists, .blockquotes,
    ]

    /// Everything `RichTextHTML` can save. That is all of today's formatting;
    /// formatting added later that HTML can't hold stays out of it.
    public static let html: RichTextFormatting = all

    /// Everything `RichTextMarkdown` can save: `all` without underline and
    /// text color, which have no Markdown form.
    public static let markdown: RichTextFormatting = all.subtracting([.underline, .textColor])

    /// Whether a block may have `style`. A paragraph always may: it is what a
    /// disallowed role becomes.
    public func allows(_ style: BlockStyle) -> Bool {
        switch style {
        case .paragraph: true
        case .heading: contains(.headings)
        case .listItem(.unordered, _): contains(.bulletedLists)
        case .listItem(.ordered, _): contains(.numberedLists)
        case .blockquote: contains(.blockquotes)
        }
    }
}
