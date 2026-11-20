// FormatCommand+Formatting.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import RichTextCore

extension FormatCommand {
    /// Whether an editor allowing `formatting` should apply this command.
    /// Removing formatting is always allowed: clearing the text color (black
    /// is the absence of one) and setting a paragraph.
    public func isAllowed(by formatting: RichTextFormatting) -> Bool {
        switch self {
        case .toggleBold: formatting.contains(.bold)
        case .toggleItalic: formatting.contains(.italic)
        case .toggleUnderline: formatting.contains(.underline)
        case .toggleStrikethrough: formatting.contains(.strikethrough)
        case let .setTextColor(color): color == nil || color == .black || formatting.contains(.textColor)
        case let .setBlockStyle(style): formatting.allows(style)
        case .toggleHeading: formatting.contains(.headings)
        case let .toggleList(kind): formatting.allows(.listItem(kind, depth: 0))
        }
    }
}
