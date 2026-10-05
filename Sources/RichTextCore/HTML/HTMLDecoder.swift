// HTMLDecoder.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation

/// Builds a semantic `AttributedString` (block markers + inline attributes) from a
/// tolerant token stream produced by `HTMLTokenizer`.
///
/// The decoder is deliberately forgiving: accepted tag variants normalize to
/// canonical attributes, unknown tags are unwrapped (their text is kept, their
/// formatting dropped), `<br>` becomes a soft line break, whitespace is
/// collapsed and block edges are trimmed. It never throws and never crashes on
/// any input.
enum HTMLDecoder {
    static func decode(_ tokens: [HTMLToken]) -> AttributedString {
        var builder = Builder()
        let ignored = ignoredTags(in: tokens)
        for (index, token) in tokens.enumerated() where !ignored.contains(index) {
            builder.consume(token)
        }
        return builder.finish()
    }

    /// The folded inline formatting active at a point in the stream.
    struct InlineState: Equatable {
        var bold = false
        var italic = false
        var underline = false
        var strikethrough = false
        var color: RichTextColor?
    }

    /// Text appended to a block by one text token, `<br>`, or `<img alt>`,
    /// plus the inline formatting it carries. Whitespace collapsing/trimming
    /// happens over these at finalize. Appends are kept separate, never merged
    /// into one string: a combining mark that starts one append must not join
    /// a space that ended the previous one, or collapsing would see a
    /// different character than the text token held.
    struct Run {
        var text: String
        var state: InlineState
    }

    /// A single ASCII whitespace scalar collapsible under HTML whitespace
    /// rules. `U+2028` (soft line break) and `U+00A0` (nbsp) are deliberately
    /// excluded — they must survive collapsing.
    static func isCollapsibleWhitespaceScalar(_ scalar: Unicode.Scalar) -> Bool {
        scalar == " " || scalar == "\t" || scalar == "\n" || scalar == "\r" || scalar == "\u{0C}"
    }

    /// A `Character` counts as collapsible whitespace when ALL of its unicode
    /// scalars are collapsible whitespace scalars.
    ///
    /// This is grapheme-aware rather than a single `Character` comparison
    /// because a literal CRLF is not the only way to end up with a CRLF
    /// grapheme cluster: `HTMLEscaping.decodeEntities` runs *inside* the
    /// tokenizer (text nodes and attribute values alike), which is AFTER the
    /// tokenizer's own line-ending normalization (`HTMLTokenizer.string`). Entities
    /// like `&#13;&#10;` (or a `&#13;` entity landing next to a literal `\n`)
    /// reassemble the exact `[0x0D, 0x0A]` cluster that normalization was
    /// meant to eliminate. Comparing whole `Character`s against `"\r"`/`"\n"`
    /// would miss that cluster entirely, since it is `!=` either one.
    ///
    /// The tokenizer's normalization is still required and NOT redundant with
    /// this: it is what keeps a literal CR out of text and attribute values,
    /// so nothing downstream has to handle one. Both layers are load-bearing.
    /// This one closes the entity-decoding gap the other cannot see.
    static func isCollapsibleWhitespace(_ char: Character) -> Bool {
        char.unicodeScalars.allSatisfy(isCollapsibleWhitespaceScalar)
    }

    /// `isCollapsibleWhitespaceScalar` for one UTF-8 byte. Every collapsible
    /// scalar is a single ASCII byte.
    static func isCollapsibleWhitespaceByte(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D || byte == 0x0C
    }

    /// Whether `text` holds any character that is not collapsible whitespace.
    /// Checking bytes gives the same answer as checking characters: a
    /// character is all whitespace exactly when every one of its bytes is.
    static func containsContent(_ text: String) -> Bool {
        text.utf8.contains { !isCollapsibleWhitespaceByte($0) }
    }

    /// Ranks a block role by how much structural information would be lost
    /// if it were silently discarded in favor of another role when two tags
    /// both want to stamp the same (still-empty) reused block — see
    /// `Builder.openBlock`.
    ///
    /// Order, least to most specific:
    ///  - `.paragraph` (0) — the default; carries no information, always loses.
    ///  - `.blockquote` (1) — a single-tag semantic role with no depth/kind
    ///    payload; losing it downgrades a quote to plain text.
    ///  - `.heading` (2) — also single-tag; losing it only affects the
    ///    presentation (font/weight) of an otherwise-intact block.
    ///  - `.listItem` (3) — ranked highest because it is produced by
    ///    *structural* nesting (`<ul>`/`<ol>` + `<li>`), not just one tag:
    ///    silently losing it drops the block out of its list entirely, which
    ///    corrupts document structure (see the `blockquote`-in-`listItem`
    ///    case in `BlockStyle`'s doc comment, D-BQ2) — a strictly worse loss
    ///    than downgrading a heading or blockquote to plain text.
    ///
    /// Equal ranks (e.g. two nested `<blockquote>`s, or nested `<li>`s of the
    /// same kind/depth) leave the current role in place, which is already
    /// correct since both sides carry the same information.
    static func specificity(of style: BlockStyle) -> Int {
        switch style {
        case .paragraph: 0
        case .blockquote: 1
        case .heading: 2
        case .listItem: 3
        }
    }
}
