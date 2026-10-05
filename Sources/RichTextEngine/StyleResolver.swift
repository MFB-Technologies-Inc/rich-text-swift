// StyleResolver.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
import RichTextCore

/// Framework-neutral description of how a run should look. The adapter turns
/// this into `UIFont`/`UIColor`/`NSParagraphStyle`; keeping the *decision* here
/// means theme application is unit-tested even though the UIKit mapping isn't.
struct RenderedStyle: Hashable, Sendable {
    var fontSize: Double
    var isBold: Bool
    var isItalic: Bool
    var isUnderlined: Bool
    var isStruckThrough: Bool
    var foregroundColor: RichTextColor?
    /// How many indent steps the block sits in: `depth + 1` for a list item,
    /// 1 for a blockquote, 0 otherwise. The adapter maps a non-zero value to
    /// paragraph indentation. (Bullet and number glyphs are drawn separately.)
    var indentLevel: Int
    /// `indentLevel` resolved to points — via `Theme.listIndent` for a list
    /// item, `Theme.blockquoteIndent` for a quote — so the adapter needs no
    /// visual constant of its own. 0 for blocks that are not indented.
    var headIndent: Double

    init(
        fontSize: Double,
        isBold: Bool = false,
        isItalic: Bool = false,
        isUnderlined: Bool = false,
        isStruckThrough: Bool = false,
        foregroundColor: RichTextColor? = nil,
        indentLevel: Int = 0,
        headIndent: Double = 0
    ) {
        self.fontSize = fontSize
        self.isBold = isBold
        self.isItalic = isItalic
        self.isUnderlined = isUnderlined
        self.isStruckThrough = isStruckThrough
        self.foregroundColor = foregroundColor
        self.indentLevel = indentLevel
        self.headIndent = headIndent
    }
}

/// Combines the semantic block role (via `Theme`) with inline attributes into a
/// concrete appearance. Rendering only — the marker remains the source of truth,
/// and nothing here is ever read back as structure.
enum StyleResolver {
    static func resolve(block: BlockStyle, typingAttributes: TypingAttributes, theme: Theme) -> RenderedStyle {
        let blockAttributes = theme.attributes(for: block)
        // Indentation is per-role, not a single scale: a list item indents by
        // its nesting depth against `listIndent`, while a blockquote is one
        // fixed step against its own `blockquoteIndent`. Resolving both to
        // (indentLevel, headIndent) here keeps the adapter free of either
        // constant.
        var indentLevel = 0
        var headIndent: Double = 0
        switch block {
        case let .listItem(_, depth):
            indentLevel = depth + 1
            headIndent = Double(indentLevel) * theme.listIndent
        case .blockquote:
            indentLevel = 1
            headIndent = theme.blockquoteIndent
        case .paragraph, .heading:
            break
        }
        return RenderedStyle(
            fontSize: blockAttributes.fontSize,
            // Inline bold adds to the theme's; it can never un-bold a heading.
            isBold: blockAttributes.isBold || typingAttributes.bold,
            isItalic: typingAttributes.italic,
            isUnderlined: typingAttributes.underline,
            isStruckThrough: typingAttributes.strikethrough,
            foregroundColor: typingAttributes.textColor ?? blockAttributes.foregroundColor,
            indentLevel: indentLevel,
            headIndent: headIndent
        )
    }

    /// Same as `resolve(block:typingAttributes:theme:)`, but accepts the
    /// optional block role a caret's `FormatState.blockStyle` can report when
    /// a selection spans blocks with differing roles. The mixed/`nil` case
    /// renders as `.paragraph` — this is the seam's decision (not the
    /// adapter's) about what to show for the caret in that situation.
    static func resolve(block: BlockStyle?, typingAttributes: TypingAttributes, theme: Theme) -> RenderedStyle {
        resolve(block: block ?? .paragraph, typingAttributes: typingAttributes, theme: theme)
    }
}
