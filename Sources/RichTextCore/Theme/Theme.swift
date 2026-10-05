// Theme.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation

/// Maps each semantic block role to the concrete visual attributes it renders
/// with. Values are framework-neutral descriptors;
/// the engine (Layer 2) turns them into real `UIFont`/attributes.
///
/// Built injection-capable on purpose: v1 ships only `.default` and does not
/// expose the injection point, so consumer-overridable theming ("B") is an
/// additive change, not a rewrite.
public struct Theme: Sendable, Equatable {
    /// Neutral visual attributes for one block role.
    public struct BlockAttributes: Sendable, Equatable {
        public var fontSize: Double
        public var isBold: Bool
        public var foregroundColor: RichTextColor?

        public init(fontSize: Double, isBold: Bool = false, foregroundColor: RichTextColor? = nil) {
            self.fontSize = fontSize
            self.isBold = isBold
            self.foregroundColor = foregroundColor
        }
    }

    public var paragraph: BlockAttributes
    public var heading1: BlockAttributes
    public var heading2: BlockAttributes
    public var heading3: BlockAttributes
    public var listItem: BlockAttributes
    /// Quoted-block appearance. A distinct entry rather than a reuse of
    /// `paragraph`: a quote that renders identically to body text is
    /// indistinguishable from one whose role was silently lost on import.
    public var blockquote: BlockAttributes
    /// Points of indentation applied per list nesting level. A visual value,
    /// so it belongs here rather than hardcoded in the platform adapter.
    public var listIndent: Double
    /// Points of indentation applied to a quoted block. Separate from
    /// `listIndent` because a quote is one fixed step, not a per-level depth
    /// — they only happen to share a value in the default theme.
    public var blockquoteIndent: Double

    // `blockquote` and `blockquoteIndent` default to the same values used by
    // `.default` below: `RichTextCore` is a shipped library product (see
    // `.library(name: "RichTextCore")` in Package.swift), so adding these two
    // required parameters would otherwise be source-breaking for any
    // consumer already constructing a `Theme`.
    public init(
        paragraph: BlockAttributes,
        heading1: BlockAttributes,
        heading2: BlockAttributes,
        heading3: BlockAttributes,
        listItem: BlockAttributes,
        blockquote: BlockAttributes = BlockAttributes(
            fontSize: 17, foregroundColor: RichTextColor(red: 110, green: 110, blue: 110)
        ),
        listIndent: Double,
        blockquoteIndent: Double = 24
    ) {
        self.paragraph = paragraph
        self.heading1 = heading1
        self.heading2 = heading2
        self.heading3 = heading3
        self.listItem = listItem
        self.blockquote = blockquote
        self.listIndent = listIndent
        self.blockquoteIndent = blockquoteIndent
    }

    /// Visual attributes for a block role. Heading levels outside 1...3 clamp
    /// to H3 (v1 supports H1–H3; the parser restricts input, this is defensive).
    public func attributes(for style: BlockStyle) -> BlockAttributes {
        switch style {
        case .paragraph:
            paragraph
        case let .heading(level):
            switch level {
            case 1: heading1
            case 2: heading2
            default: heading3
            }
        case .listItem:
            listItem
        case .blockquote:
            blockquote
        }
    }

    /// The single fixed appearance shipped in v1.
    public static let `default` = Theme(
        paragraph: BlockAttributes(fontSize: 17),
        heading1: BlockAttributes(fontSize: 28, isBold: true),
        heading2: BlockAttributes(fontSize: 22, isBold: true),
        heading3: BlockAttributes(fontSize: 20, isBold: true),
        listItem: BlockAttributes(fontSize: 17),
        // Body size and weight, set apart by a muted foreground plus the
        // indent below — the conventional blockquote treatment. Deliberately
        // not black: black is the *absence* of a color everywhere in this
        // system, so a black theme color would be indistinguishable from
        // "unthemed" to `StyleResolver`.
        blockquote: BlockAttributes(fontSize: 17, foregroundColor: RichTextColor(red: 110, green: 110, blue: 110)),
        listIndent: 24,
        blockquoteIndent: 24
    )
}
