// RichTextControl.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
import RichTextCore
import RichTextEngine

/// A heading level the toolbar can offer. v1 ships H1–H3.
public enum HeadingLevel: Int, Hashable, Sendable, CaseIterable {
    case h1 = 1
    case h2 = 2
    case h3 = 3
}

/// A built-in toolbar control.
///
/// The consumer picks and orders these; the package renders them:
///
/// ```swift
/// RichTextEditor(text: $doc)
///     .richTextToolbar([.bold, .italic, .textColor, .unorderedList, .heading(.h1)])
/// ```
public enum RichTextControl: Hashable, Sendable {
    case bold
    case italic
    case underline
    case strikethrough
    case textColor
    case unorderedList
    case orderedList
    case heading(HeadingLevel)
}

/// The mapping below is deliberately **internal**: its signatures name
/// `FormatCommand`/`FormatState`, and exposing those publicly would open the
/// command/state seam that v1 deliberately keeps closed. Promoting
/// this to public is the additive "bring your own toolbar" work.
extension RichTextControl {
    /// The command this control sends when tapped.
    ///
    /// `nil` for `.textColor` alone: there is no fixed command to send because
    /// the color comes from the system picker's own binding, which issues
    /// `.setTextColor(_:)` directly as the user picks; picking
    /// black is how the user removes the color, since the picker cannot bind
    /// an optional.
    var command: FormatCommand? {
        switch self {
        case .bold: .toggleBold
        case .italic: .toggleItalic
        case .underline: .toggleUnderline
        case .strikethrough: .toggleStrikethrough
        case .textColor: nil
        case .unorderedList: .toggleList(.unordered)
        case .orderedList: .toggleList(.ordered)
        case let .heading(level): .toggleHeading(level.rawValue)
        }
    }

    /// Whether this control renders as active for the given selection.
    ///
    /// `.mixed` reads as inactive alongside `.off`: the engine
    /// turns a mixed selection fully *on* when toggled, so an inactive button
    /// correctly predicts its own tap. A `nil` `blockStyle` — a selection
    /// spanning differing block roles — is likewise inactive.
    func isActive(in state: FormatState) -> Bool {
        switch self {
        case .bold: return state.bold == .on
        case .italic: return state.italic == .on
        case .underline: return state.underline == .on
        case .strikethrough: return state.strikethrough == .on
        case .textColor: return state.textColor != nil && !state.isTextColorMixed
        case .unorderedList, .orderedList, .heading:
            guard let block = state.blockStyle else { return false }
            return matchesBlock(block)
        }
    }

    private func matchesBlock(_ block: BlockStyle) -> Bool {
        switch (self, block) {
        case (.unorderedList, .listItem(.unordered, _)): true
        case (.orderedList, .listItem(.ordered, _)): true
        case let (.heading(level), .heading(blockLevel)): level.rawValue == blockLevel
        default: false
        }
    }

    /// SF Symbol name, or `nil` for a control drawn as text (or, for
    /// `.textColor`, as neither: see below).
    var systemImage: String? {
        switch self {
        case .bold: "bold"
        case .italic: "italic"
        case .underline: "underline"
        case .strikethrough: "strikethrough"
        // `RichTextToolbar.button(for:)` branches to `TextColorControl` before
        // this property is ever consulted, so `.textColor` has no rendered
        // symbol or text — the system picker's own swatch is the control's
        // visual, not an SF Symbol standing in for it.
        case .textColor: nil
        case .unorderedList: "list.bullet"
        case .orderedList: "list.number"
        // SF Symbols has no clean H1/H2/H3 equivalent, so headings are drawn
        // as text.
        case .heading: nil
        }
    }

    /// Text to draw when there is no symbol (except `.textColor`, which has
    /// neither — see `systemImage`).
    var textLabel: String? {
        switch self {
        case let .heading(level): "H\(level.rawValue)"
        case .bold, .italic, .underline, .strikethrough,
             .textColor, .unorderedList, .orderedList: nil
        }
    }

    /// VoiceOver label, and the accessibility identifier the simulator tests
    /// search the hosted hierarchy for.
    var accessibilityLabel: String {
        switch self {
        case .bold: "Bold"
        case .italic: "Italic"
        case .underline: "Underline"
        case .strikethrough: "Strikethrough"
        case .textColor: "Text color"
        case .unorderedList: "Bulleted list"
        case .orderedList: "Numbered list"
        case let .heading(level): "Heading \(level.rawValue)"
        }
    }
}
