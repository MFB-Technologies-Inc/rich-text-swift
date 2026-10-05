// HTMLTagClasses.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation

/// What kind of element a tag name is, for the tolerant importer.
///
/// The classification is deliberately **inverted** relative to the obvious
/// design: rather than listing the block-level tags we know about, we list the
/// *inline* ones and treat everything else as block-level. Real-world HTML
/// (Word, Outlook, arbitrary web paste) contains block elements nobody
/// enumerated in advance, and the two failure modes are not symmetric:
///
/// - Misclassifying a block as inline **merges adjacent lines**, sometimes
///   jamming words together with no separator. The text is corrupted.
/// - Misclassifying an inline as a block **inserts a paragraph break**. The
///   text survives, and the damage is visible rather than silent.
///
/// So unknown ⇒ block.
enum HTMLTagClasses {
    /// Elements whose content flows inside the surrounding block. Everything
    /// here either carries formatting we map, or is a phrasing wrapper we
    /// unwrap while keeping its text in place.
    static let inline: Set<String> = [
        // Formatting we map to attributes.
        "b", "strong", "i", "em", "u", "ins", "s", "strike", "del", "span", "font",
        // Phrasing content we unwrap but must not break a line for.
        "a", "abbr", "acronym", "bdi", "bdo", "big", "cite", "code", "data", "dfn",
        "kbd", "label", "mark", "nobr", "q", "rp", "rt", "ruby", "samp", "small",
        "sub", "sup", "time", "tt", "var", "output",
        // Wrapper elements that only ever contain phrasing content inside a
        // line — unwrapping them must not break the surrounding paragraph.
        // `object` moved here from `skipContent`: we don't render embeds, and
        // unwrapping its fallback content is strictly safer than suppressing it.
        "picture", "button", "video", "audio", "canvas", "object", "map",
    ]

    /// Elements with no end tag. These must be classified before anything else:
    /// treating one as a block or skip container would leave that container
    /// open for the remainder of the document.
    static let void: Set<String> = [
        "area", "base", "br", "col", "embed", "hr", "img", "input",
        "link", "meta", "param", "source", "track", "wbr",
    ]

    /// Elements whose *text content* is machine data, not prose. Their content
    /// is suppressed entirely rather than unwrapped — otherwise stylesheet and
    /// script source appears as visible text in the user's document. Word and
    /// Outlook HTML carry very large `<style>` blocks.
    static let skipContent: Set<String> = [
        "script", "style", "head", "title", "meta", "link", "noscript",
        "template", "svg", "math", "iframe",
    ]

    /// Skip elements whose content a browser reads as text up to the first end
    /// tag of the same name, never as markup: a `"</div>"` or `"<script>"`
    /// string inside a script is not a tag.
    static let rawText: Set<String> = ["script", "style", "title", "iframe", "noscript"]

    /// True when a tag should open and close a block boundary.
    ///
    /// A tag whose name contains a colon is an XML namespace prefix
    /// (`o:p`, `w:sdt`, `v:shapetype`, `st1:place`, …) — the way Office HTML
    /// (Word, Outlook) marks its own vocabulary. This is a deliberate,
    /// narrow exception to the file's "unknown ⇒ block" default: that
    /// default fails safe for unknown *semantic* elements we've simply never
    /// seen, where the two failure modes are asymmetric (a missed block
    /// boundary corrupts text; an extra one is just visible noise). Namespaced
    /// tags are different — they are *known* to carry no block semantics we
    /// could honor even if we recognized them by name, and they are not rare:
    /// Word emits `<o:p></o:p>` inside nearly every `<p>`, so treating them as
    /// unknown-block turns every paragraph in a pasted Word document into two.
    /// A set can't enumerate an open-ended set of namespace prefixes, so this
    /// is a name check rather than a membership test like the others below.
    static func isBlockLevel(_ tag: String) -> Bool {
        if tag.contains(":") {
            return false
        }
        return !inline.contains(tag) && !void.contains(tag) && !skipContent.contains(tag)
    }
}
