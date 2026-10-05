// FormatState.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
import RichTextCore

/// Whether an attribute holds across the whole selection, nowhere in it, or
/// only part of it. Drives toolbar active/inactive/indeterminate state (M5).
public enum TriState: Hashable, Sendable {
    case on
    case off
    case mixed
}

/// The inline (character-level) attributes v1 supports. Deliberately a small
/// closed enum so command handling and state reading stay table-driven.
public enum InlineFlag: Hashable, Sendable, CaseIterable {
    case bold
    case italic
    case underline
    case strikethrough
}

/// The formatting of the current selection — the "state" half of the internal
/// command/state seam (dev-plan Decision #6).
public struct FormatState: Hashable, Sendable {
    public var bold: TriState
    public var italic: TriState
    public var underline: TriState
    public var strikethrough: TriState
    /// The uniform text color across the selection; `nil` means "no color set"
    /// (i.e. theme default). Only meaningful when `isTextColorMixed` is false.
    public var textColor: RichTextColor?
    /// True when the selection contains more than one distinct color value.
    public var isTextColorMixed: Bool
    /// The uniform block role across the selection; `nil` when blocks differ.
    public var blockStyle: BlockStyle?

    public init(
        bold: TriState = .off,
        italic: TriState = .off,
        underline: TriState = .off,
        strikethrough: TriState = .off,
        textColor: RichTextColor? = nil,
        isTextColorMixed: Bool = false,
        blockStyle: BlockStyle? = .paragraph
    ) {
        self.bold = bold
        self.italic = italic
        self.underline = underline
        self.strikethrough = strikethrough
        self.textColor = textColor
        self.isTextColorMixed = isTextColorMixed
        self.blockStyle = blockStyle
    }

    public subscript(flag: InlineFlag) -> TriState {
        switch flag {
        case .bold: bold
        case .italic: italic
        case .underline: underline
        case .strikethrough: strikethrough
        }
    }
}
