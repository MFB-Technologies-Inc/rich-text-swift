// MarkdownEscaping.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation

/// Backslash escapes for text written into Markdown, so a literal `*`, `#`,
/// `1.` or `>` never becomes formatting.
enum MarkdownEscaping {
    /// Escaped wherever they appear: each can open inline syntax mid-line
    /// (emphasis, code, strikethrough, links, autolinks and HTML, entities,
    /// table cells), or is the escape character itself.
    private static let inlineSpecial: Set<Character> = ["\\", "*", "_", "`", "~", "[", "]", "<", "&", "|"]

    /// Read as block syntax at the start of a line: a heading, a quote, a
    /// bullet or rule, or a setext underline.
    private static let lineStartSpecial: Set<Character> = ["#", ">", "-", "+", "="]

    static func escapeInline(_ text: String) -> String {
        escape(text, also: [])
    }

    /// `escapeInline`, plus whatever would make the start of a line read as a
    /// block: one of `lineStartSpecial`, or an ordered-list number (`1.`, `1)`).
    static func escapeLineStart(_ text: String) -> String {
        guard let first = text.first else {
            return text
        }
        if lineStartSpecial.contains(first) {
            return "\\" + escapeInline(text)
        }
        let digits = text.prefix { $0.isASCII && $0.isNumber }
        let rest = text.dropFirst(digits.count)
        if !digits.isEmpty, let marker = rest.first, marker == "." || marker == ")" {
            return digits + "\\" + escapeInline(String(rest))
        }
        return escapeInline(text)
    }

    /// `escapeInline`, plus every `#`: a heading's trailing `#`s would
    /// otherwise be read as its closing sequence and dropped.
    static func escapeHeading(_ text: String) -> String {
        escape(text, also: ["#"])
    }

    private static func escape(_ text: String, also extra: Set<Character>) -> String {
        var out = ""
        for character in text {
            if inlineSpecial.contains(character) || extra.contains(character) {
                out.append("\\")
            }
            out.append(character)
        }
        // A bare URL would be autolinked (GFM), and the link would take in
        // any delimiter written right after it.
        return out
            .replacingOccurrences(of: "://", with: "\\://")
            .replacingOccurrences(of: "www.", with: "www\\.")
    }
}
