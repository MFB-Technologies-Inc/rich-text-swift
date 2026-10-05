// SemanticStringBuilders.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
@testable import RichTextCore

/// Test helpers for constructing semantic AttributedStrings concisely.
enum Sem {
    /// One block of plain text with a block style.
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

    /// Apply an inline attribute to an entire block's text (helper for tests).
    static func bold(_ a: AttributedString) -> AttributedString {
        var copy = a
        copy.bold = true
        return copy
    }
}
