// RichTextMarkdown.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation

/// The public Markdown serialization entry points: CommonMark plus GFM
/// strikethrough.
///
/// Like `RichTextHTML`, `encode`/`decode` operate on the *semantic* model
/// only (block markers + inline attributes). Theme and font rendering are
/// applied by the editing engine, not here.
public enum RichTextMarkdown {
    /// Encodes `attributedString` to Markdown in one canonical style:
    /// `**bold**`, `*italic*`, `~~strike~~`, `-` bullets, `1.` numbering, `#`
    /// headings and `>` quotes. Text is escaped so a literal `*`, `#` or `1.`
    /// never becomes formatting. This is an editor that saves to Markdown, not
    /// a Markdown source editor, so hand-written Markdown is rewritten in this
    /// style on save (`_a_` becomes `*a*`).
    ///
    /// Underline and text color have no Markdown form and are dropped, text
    /// kept. Where two marks touch, or a mark sits next to punctuation, an
    /// empty HTML comment (`<!-- -->`) keeps them apart; `decode(_:)` ignores
    /// it.
    ///
    /// `decode(encode(x)) == x` holds only for documents in **canonical
    /// form**:
    ///
    /// - **Whitespace-normalized**, as for `RichTextHTML`: single interior
    ///   spaces, and none at a block's edges or next to a soft line break.
    /// - **No empty blocks.** Markdown can't hold an empty paragraph or list
    ///   item, so they collapse.
    /// - **No underline or text color**, and no explicit black `textColor`.
    /// - **Headings are H1–H3 and hold no soft line break.** A Markdown
    ///   heading is one line, so its breaks are written as spaces.
    /// - **No soft line break at a block's edge, and no mark that starts or
    ///   ends on whitespace or a soft line break.** `**a **` is not bold in
    ///   Markdown, so the encoder moves such whitespace outside the mark.
    public static func encode(_ attributedString: AttributedString) -> String {
        MarkdownEncoder.encode(attributedString)
    }

    /// Decodes Markdown into the semantic model. Import is tolerant: content
    /// the model can't hold yet (code, tables, images, links, rules, raw
    /// HTML) keeps its text and drops its formatting, matching the HTML
    /// policy. Headings deeper than H3 become H3, and a list inside a quote
    /// becomes a plain list. See `encode(_:)` for when `decode(encode(x)) == x`
    /// holds.
    public static func decode(_ markdown: String) -> AttributedString {
        MarkdownDecoder.decode(markdown)
    }
}
