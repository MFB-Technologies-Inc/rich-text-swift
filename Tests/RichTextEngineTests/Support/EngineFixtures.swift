// EngineFixtures.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
import RichTextCore

/// Test helpers for building semantic AttributedStrings concisely.
/// (Mirrors `Sem` in RichTextCoreTests; duplicated because test targets
/// cannot import each other.)
enum Sem {
    /// One block of text carrying a block style.
    static func block(_ text: String, _ style: BlockStyle = .paragraph) -> AttributedString {
        var a = AttributedString(text)
        a.blockStyle = style
        return a
    }

    /// Join blocks with "\n" separators into one flat model.
    static func doc(_ blocks: AttributedString...) -> AttributedString {
        var result = AttributedString()
        for (i, b) in blocks.enumerated() {
            if i > 0 {
                result += AttributedString("\n")
            }
            result += b
        }
        return result
    }

    /// Apply inline attributes to an entire block.
    static func with(
        _ a: AttributedString,
        bold: Bool? = nil,
        italic: Bool? = nil,
        underline: Bool? = nil,
        strikethrough: Bool? = nil,
        color: RichTextColor? = nil
    ) -> AttributedString {
        var copy = a
        if let bold {
            copy.bold = bold
        }
        if let italic {
            copy.italic = italic
        }
        if let underline {
            copy.underline = underline
        }
        if let strikethrough {
            copy.strikethrough = strikethrough
        }
        if let color {
            copy.textColor = color
        }
        return copy
    }
}
