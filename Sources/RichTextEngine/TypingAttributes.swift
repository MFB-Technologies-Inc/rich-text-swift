// TypingAttributes.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
import RichTextCore

/// Formatting that applies to text the user types next, when the caret itself
/// carries no attributes yet (standard editor "typing attributes" behavior).
///
/// `blockStyle` is the **pending** block role for an *empty* block: Foundation
/// cannot store an attribute on zero-length content, so the role lives here
/// until characters exist to carry it (M3 decision D13).
public struct TypingAttributes: Hashable, Sendable {
    public var bold: Bool
    public var italic: Bool
    public var underline: Bool
    public var strikethrough: Bool
    public var textColor: RichTextColor?
    public var blockStyle: BlockStyle?

    public init(
        bold: Bool = false,
        italic: Bool = false,
        underline: Bool = false,
        strikethrough: Bool = false,
        textColor: RichTextColor? = nil,
        blockStyle: BlockStyle? = nil
    ) {
        self.bold = bold
        self.italic = italic
        self.underline = underline
        self.strikethrough = strikethrough
        self.textColor = textColor
        self.blockStyle = blockStyle
    }

    public subscript(flag: InlineFlag) -> Bool {
        get {
            switch flag {
            case .bold: bold
            case .italic: italic
            case .underline: underline
            case .strikethrough: strikethrough
            }
        }
        set {
            switch flag {
            case .bold: bold = newValue
            case .italic: italic = newValue
            case .underline: underline = newValue
            case .strikethrough: strikethrough = newValue
            }
        }
    }
}
