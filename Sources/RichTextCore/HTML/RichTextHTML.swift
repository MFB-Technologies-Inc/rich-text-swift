// RichTextHTML.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation

/// The public simple-HTML serialization entry points.
///
/// `encode`/`decode` operate on the *semantic* model only (block markers +
/// inline attributes). Theme/font rendering is applied by the editing engine,
/// not here.
public enum RichTextHTML {
    /// The character used to represent a soft line break (imported `<br>`)
    /// inside a block. Distinct from `\n`, which separates blocks.
    public static let softLineBreak: Character = "\u{2028}"

    /// Encodes `attributedString` to HTML, emitting text verbatim (only
    /// escaping reserved characters). `decode(_:)`, by contrast, applies
    /// standard HTML whitespace semantics: it collapses runs of ASCII
    /// whitespace and trims leading/trailing whitespace at block edges.
    ///
    /// Consequently the round-trip identity `decode(encode(x)) == x` holds
    /// only for models in **canonical form** — i.e. a document satisfying
    /// both of the following:
    ///
    /// - **Whitespace-normalized**: blocks use single interior spaces and
    ///   have no leading/trailing/tab/newline runs. Non-normalized whitespace
    ///   is not preserved across a round trip. U+00A0 (nbsp) and U+2028 (soft
    ///   line break) are not ASCII whitespace and are always preserved.
    /// - **No explicit black `textColor`**: black is treated as the absence
    ///   of a text color everywhere in the system (`RichTextColor.black`;
    ///   see `EngineCore.normalizingDefaultColor` for where that rule is
    ///   enforced on documents entering the engine). `encode(_:)` omits the
    ///   color span for a black run rather than emitting `color:#000000`, so
    ///   a document carrying explicit black is not fixed by this round trip
    ///   — `decode(encode(x))` strips the color rather than reproducing it.
    ///   This module's own command layer and decoder both normalize black
    ///   away before `encode(_:)` ever sees it, but `RichTextColor` and the
    ///   model's attribute keys are public, so a caller can construct a
    ///   non-canonical document directly and call `encode(_:)` on it.
    public static func encode(_ attributedString: AttributedString) -> String {
        HTMLEncoder.encode(attributedString)
    }

    /// Decodes HTML into the semantic model. See `encode(_:)` for the two
    /// preconditions (whitespace normalization, no explicit black
    /// `textColor`) a model must satisfy for `decode(encode(x)) == x` to
    /// hold.
    public static func decode(_ html: String) -> AttributedString {
        HTMLDecoder.decode(HTMLTokenizer.tokenize(html))
    }
}
