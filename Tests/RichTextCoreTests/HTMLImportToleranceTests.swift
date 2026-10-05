// HTMLImportToleranceTests.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
@testable import RichTextCore
import Testing

/// Import-tolerance regression tests for real-world HTML shapes.
///
/// The inputs are verbatim output from the two families of editor that most
/// commonly produce stored HTML: a WebKit `contenteditable` (which emits a
/// `<div>` per line) and the draft-js/Lexical family (which stores `<ins>` and
/// `<del>` for underline and strikethrough).
struct HTMLImportToleranceTests {
    /// `<ins>` is the underline tag in the stored web dialect, for both the
    /// draft-js era and Lexical today. `<del>` was already handled; its pair
    /// was missed, so every underline written by such an editor was lost.
    @Test func insDecodesAsUnderline() {
        let decoded = RichTextHTML.decode("<p><ins>underlined</ins></p>")
        #expect(RichTextHTML.encode(decoded) == "<p><u>underlined</u></p>")
    }

    /// Guards the asymmetry that caused this: the `<del>`/`<ins>` pair must
    /// stay symmetric. If someone adds a tag to one side only, this fails.
    @Test func delAndInsAreSymmetric() {
        #expect(RichTextHTML.encode(RichTextHTML.decode("<p><del>x</del></p>")) == "<p><s>x</s></p>")
        #expect(RichTextHTML.encode(RichTextHTML.decode("<p><ins>x</ins></p>")) == "<p><u>x</u></p>")
    }

    @Test func insCombinesWithOtherInlineFormatting() {
        let decoded = RichTextHTML.decode("<p><strong><em><ins>all</ins></em></strong></p>")
        #expect(RichTextHTML.encode(decoded) == "<p><b><i><u>all</u></i></b></p>")
    }

    /// Void elements never have an end tag. Classifying one as block-level or
    /// skip-content would leave a boundary open for the rest of the document —
    /// e.g. a bare `<link>` in a Word paste would swallow the whole note.
    @Test func voidElementsAreNeitherBlockNorSkipContainers() {
        #expect(HTMLTagClasses.void.contains("meta"))
        #expect(HTMLTagClasses.void.contains("link"))
        #expect(HTMLTagClasses.void.contains("img"))
        #expect(HTMLTagClasses.void.contains("hr"))
        #expect(!HTMLTagClasses.isBlockLevel("img"))
    }

    @Test func knownInlineTagsAreNotBlockLevel() {
        for tag in ["span", "a", "font", "code", "sub", "sup", "mark", "small", "q"] {
            #expect(!HTMLTagClasses.isBlockLevel(tag), "\(tag) must stay inline")
        }
    }

    /// The failing-safe rule: anything not known to be inline is treated as a
    /// block. A spurious block boundary loses far less than a spurious merge.
    /// Namespaced tags (`o:p`) are the deliberate exception — see
    /// `namespacedTagsAreNeverBlockLevel` below.
    @Test func unknownTagsAreTreatedAsBlockLevel() {
        #expect(HTMLTagClasses.isBlockLevel("div"))
        #expect(HTMLTagClasses.isBlockLevel("section"))
        #expect(HTMLTagClasses.isBlockLevel("custom-thing")) // never seen before
    }

    // MARK: - Namespaced Office tags (Word/Outlook `o:p`, `w:sdt`, etc.)

    /// XML-namespaced tags carry no block semantics we can honor, and Word
    /// puts one in essentially every paragraph (`<o:p></o:p>`), so treating
    /// them as unknown-block would insert a blank paragraph after every
    /// single paragraph in a pasted Word document.
    @Test func namespacedTagsAreNeverBlockLevel() {
        #expect(!HTMLTagClasses.isBlockLevel("o:p"))
        #expect(!HTMLTagClasses.isBlockLevel("w:sdt"))
        #expect(!HTMLTagClasses.isBlockLevel("v:shapetype"))
        #expect(!HTMLTagClasses.isBlockLevel("st1:place"))
    }

    /// The regression this change fixes: Word emits `<o:p></o:p>` inside
    /// nearly every `<p>`. At v1.0.0 this decoded to a single paragraph; the
    /// unknown-⇒-block inversion turned it into a spurious blank paragraph.
    @Test func namespacedOfficeTagDoesNotAddABlankParagraph() {
        #expect(RichTextHTML.encode(RichTextHTML.decode("<p>text<o:p></o:p></p>")) == "<p>text</p>")
    }

    /// Same shape repeated across two paragraphs, the actual corpus this
    /// fix exists to serve.
    @Test func namespacedOfficeTagsAcrossMultipleParagraphsDoNotAddBlankParagraphs() {
        let html = "<p>Hello world<o:p></o:p></p><p>Second para<o:p></o:p></p>"
        #expect(RichTextHTML.encode(RichTextHTML.decode(html))
            == "<p>Hello world</p>\n<p>Second para</p>")
    }

    /// A namespaced tag that actually carries content (`<w:t>`, a Word run
    /// wrapper) must unwrap in place, not split the paragraph.
    @Test func namespacedOfficeTagWithContentStaysInline() {
        #expect(RichTextHTML.encode(RichTextHTML.decode("<p>a<w:t>b</w:t>c</p>")) == "<p>abc</p>")
    }

    // MARK: - Phrasing-content wrapper tags (<picture>, <video>, etc.)

    /// `<picture>` only ever wraps phrasing content (`<source>`/`<img>`); it
    /// must not split its surrounding paragraph the way an unknown block tag
    /// would.
    @Test func pictureWrapperDoesNotBreakItsParagraph() {
        let html = "<p>a <picture><img alt=\"pic\"></picture> b</p>"
        #expect(RichTextHTML.encode(RichTextHTML.decode(html)) == "<p>a pic b</p>")
    }

    @Test func styleAndScriptBodiesAreNotVisibleText() {
        #expect(RichTextHTML.encode(RichTextHTML.decode("<style>p{color:red}</style><p>ok</p>")) == "<p>ok</p>")
        #expect(RichTextHTML.encode(RichTextHTML.decode("<p>ok</p><script>alert(1)</script>")) == "<p>ok</p>")
    }

    @Test func documentHeadIsSkippedEntirely() {
        let html = "<html><head><title>T</title></head><body><p>ok</p></body></html>"
        #expect(RichTextHTML.encode(RichTextHTML.decode(html)) == "<p>ok</p>")
    }

    /// A bare void element inside a skip set must not open a skip region — if
    /// `<meta>` opened one, everything after it would vanish.
    @Test func bareVoidMetaDoesNotSwallowTheDocument() {
        #expect(RichTextHTML.encode(RichTextHTML.decode("<meta charset=\"utf-8\"><p>ok</p>")) == "<p>ok</p>")
        #expect(RichTextHTML.encode(RichTextHTML.decode("<link rel=\"x\"><p>ok</p>")) == "<p>ok</p>")
    }

    /// Nested same-name tags must not end the skip region early. Uses `<svg>`,
    /// which really nests: a raw-text `<style>` ends at its first `</style>`.
    @Test func nestedSkipTagsTrackDepth() {
        let html = "<svg>a<svg>b</svg>c</svg><p>ok</p>"
        #expect(RichTextHTML.encode(RichTextHTML.decode(html)) == "<p>ok</p>")
    }

    /// A `contenteditable` that never sets `defaultParagraphSeparator` gets
    /// WebKit's default block separator — a `<div>` per line. Legacy content
    /// from such an editor is overwhelmingly this shape.
    @Test func divPerLineBecomesOneBlockPerLine() {
        let compact = RichTextHTML.decode("<div>First line</div><div>Second line</div>")
        #expect(RichTextHTML.encode(compact) == "<p>First line</p>\n<p>Second line</p>")
    }

    /// Editors that pretty-print their HTML store the same content with
    /// newlines and indentation between tags.
    @Test func prettyPrintedDivPerLineBecomesOneBlockPerLine() {
        let pretty = RichTextHTML.decode("<div>Line one</div>\n<div>Line two</div>")
        #expect(RichTextHTML.encode(pretty) == "<p>Line one</p>\n<p>Line two</p>")
    }

    @Test func unmappedHeadingLevelsStaySeparateBlocks() {
        #expect(RichTextHTML.encode(RichTextHTML.decode("<h4>four</h4><h5>five</h5>"))
            == "<p>four</p>\n<p>five</p>")
    }

    @Test func tableCellsDoNotMerge() {
        let html = "<table><tr><td>a</td><td>b</td></tr></table>"
        #expect(RichTextHTML.encode(RichTextHTML.decode(html)) == "<p>a</p>\n<p>b</p>")
    }

    /// A block wrapper that immediately contains another block must not leave
    /// an empty paragraph behind.
    @Test func documentWrappersDoNotEmitEmptyParagraphs() {
        let html = "<html><body><div><p>x</p></div></body></html>"
        #expect(RichTextHTML.encode(RichTextHTML.decode(html)) == "<p>x</p>")
    }

    /// ...but a deliberately empty paragraph is content and must survive.
    @Test func deliberateEmptyParagraphSurvives() {
        #expect(RichTextHTML.encode(RichTextHTML.decode("<p>a</p><p></p><p>b</p>"))
            == "<p>a</p>\n<p></p>\n<p>b</p>")
    }

    /// `<p>` inside `<li>` must keep the list role, not demote to paragraph
    /// and not emit a leading empty item.
    @Test func paragraphInsideListItemKeepsTheListRole() {
        #expect(RichTextHTML.encode(RichTextHTML.decode("<ul><li><p>a</p></li></ul>"))
            == "<ul><li>a</li></ul>")
    }

    /// Text before a nested block flushes as its own block rather than merging.
    @Test func textBeforeANestedBlockIsItsOwnBlock() {
        #expect(RichTextHTML.encode(RichTextHTML.decode("<div>a<div>b</div></div>"))
            == "<p>a</p>\n<p>b</p>")
    }

    /// Inline elements must NOT gain a block boundary from this change.
    @Test func inlineElementsStillDoNotBreakBlocks() {
        #expect(RichTextHTML.encode(RichTextHTML.decode("<p>see <a href=\"https://x.com\">this link</a> ok</p>"))
            == "<p>see this link ok</p>")
        #expect(RichTextHTML.encode(RichTextHTML.decode("<p>a<span>b</span>c</p>")) == "<p>abc</p>")
    }

    // MARK: - Whitespace-only wrapper blocks (pretty-printed HTML)

    /// The real corpus is pretty-printed: whitespace/newlines between wrapper
    /// tags must not defeat the empty-wrapper reuse rule and leak a spurious
    /// `<p></p>`.
    @Test func prettyPrintedWrapperWithNewlineDoesNotEmitEmptyParagraph() {
        let html = "<div>\n  <p>a</p>\n</div>"
        #expect(RichTextHTML.encode(RichTextHTML.decode(html)) == "<p>a</p>")
    }

    @Test func prettyPrintedDocumentWrappersDoNotEmitEmptyParagraphs() {
        let html = "<html>\n<body>\n<div>a</div>\n<div>b</div>\n</body>\n</html>"
        #expect(RichTextHTML.encode(RichTextHTML.decode(html)) == "<p>a</p>\n<p>b</p>")
    }

    @Test func prettyPrintedHeadingWrapperDoesNotEmitEmptyParagraph() {
        let html = "<section>\n<h1>t</h1>\n</section>"
        #expect(RichTextHTML.encode(RichTextHTML.decode(html)) == "<h1>t</h1>")
    }

    // MARK: - <hr> is a block boundary despite being void

    /// `<hr>` is semantically block-level; letting it fall to the inline-
    /// unwrap path (because it's also void) would jam surrounding text
    /// together — the exact failure this whole change exists to prevent.
    @Test func hrSplitsSurroundingTextIntoSeparateBlocks() {
        #expect(RichTextHTML.encode(RichTextHTML.decode("<div>a<hr>b</div>"))
            == "<p>a</p>\n<p>b</p>")
    }

    /// `<hr>` alone reduces to the same "genuinely empty document" case as
    /// `decode("")`, which already encodes as a single empty paragraph — the
    /// encoder always emits at least one block, since Foundation can't carry
    /// a `blockStyle` on zero-length content. That single `<p></p>` is the
    /// existing empty-document representation, not a bug `<hr>` introduces.
    @Test func hrAloneMatchesTheEmptyDocumentRepresentation() {
        #expect(RichTextHTML.encode(RichTextHTML.decode("<hr>")) == "<p></p>")
        #expect(RichTextHTML.decode("<hr>").characters.isEmpty)
    }

    @Test func leadingHrProducesNoStrayEmptyParagraph() {
        #expect(RichTextHTML.encode(RichTextHTML.decode("<hr><p>a</p>")) == "<p>a</p>")
    }

    @Test func trailingHrProducesNoStrayEmptyParagraph() {
        #expect(RichTextHTML.encode(RichTextHTML.decode("<p>a</p><hr>")) == "<p>a</p>")
    }

    // MARK: - <img> alt text

    /// Images are a documented v1 deferral, but silently deleting one leaves
    /// nothing behind. Keep the alt text so the content is recoverable.
    @Test func imageKeepsItsAltText() {
        let html = "<p><img src=\"https://x.com/a.png\" alt=\"pic\"></p>"
        #expect(RichTextHTML.encode(RichTextHTML.decode(html)) == "<p>pic</p>")
    }

    @Test func imageWithoutAltIsDroppedSilently() {
        #expect(RichTextHTML.encode(RichTextHTML.decode("<p>a<img src=\"x.png\">b</p>")) == "<p>ab</p>")
    }

    // MARK: - CRLF normalization

    @Test func crlfIsNotPreservedInsideABlock() {
        let decoded = RichTextHTML.decode("<p>line one\r\nline two</p>")
        #expect(RichTextHTML.encode(decoded) == "<p>line one line two</p>")
        // Grapheme-level, NOT scalar-level: Swift fuses CRLF into a single
        // `Character`, so `"a\r\nb".contains("\r")` is `false` even when a
        // `\r\n` survives — that comparison could never observe the bug this
        // test exists to catch. Compare `unicodeScalars` instead, which sees
        // the raw 0x0D byte regardless of what grapheme it was fused into.
        #expect(!String(decoded.characters).unicodeScalars.contains("\r"))
    }

    /// Entity-encoded CRLF (`&#13;&#10;`) is decoded by `HTMLEscaping.decodeEntities`
    /// *inside* the tokenizer, after the tokenizer has normalized literal line
    /// endings. That normalization alone can't see a CRLF cluster
    /// entities only create later, so the whitespace check itself must be
    /// grapheme-aware. Common in Word/Outlook/CMS-exported HTML.
    @Test func crlfFromDecimalEntitiesIsNotPreservedInsideABlock() {
        let decoded = RichTextHTML.decode("<p>a&#13;&#10;b</p>")
        #expect(RichTextHTML.encode(decoded) == "<p>a b</p>")
        #expect(!String(decoded.characters).unicodeScalars.contains("\r"))
    }

    @Test func crlfFromHexEntitiesIsNotPreservedInsideABlock() {
        let decoded = RichTextHTML.decode("<p>a&#x0D;&#x0A;b</p>")
        #expect(RichTextHTML.encode(decoded) == "<p>a b</p>")
        #expect(!String(decoded.characters).unicodeScalars.contains("\r"))
    }

    /// An entity-produced CR immediately followed by a literal LF forms the
    /// same CRLF grapheme cluster as a literal `\r\n`, just assembled from two
    /// different sources.
    @Test func entityCRAdjacentToLiteralLFIsNotPreserved() {
        let decoded = RichTextHTML.decode("<p>a&#13;\nb</p>")
        #expect(RichTextHTML.encode(decoded) == "<p>a b</p>")
        #expect(!String(decoded.characters).unicodeScalars.contains("\r"))
    }

    /// `<img alt="...">` text is decoded via the tokenizer's attribute-value
    /// entity decoding (`HTMLTokenizer.swift` around line 195), a separate
    /// path from text-node entity decoding — exercise it too.
    @Test func imgAltEntityCRLFIsNotPreserved() {
        let decoded = RichTextHTML.decode("<p><img alt=\"a&#13;&#10;b\"></p>")
        #expect(RichTextHTML.encode(decoded) == "<p>a b</p>")
        #expect(!String(decoded.characters).unicodeScalars.contains("\r"))
    }

    /// Re-encode stability: encoding a decoded document twice must be
    /// idempotent. This is the invariant the entity-CRLF bug violated —
    /// the first encode produced `<p>a\r\nb</p>` (non-canonical), and
    /// re-decoding+encoding that collapsed the CRLF, so `once != twice`.
    @Test func reencodeStabilityForEntityCRLF() {
        let decoded = RichTextHTML.decode("<p>a&#13;&#10;b</p>")
        let once = RichTextHTML.encode(decoded)
        let twice = RichTextHTML.encode(RichTextHTML.decode(once))
        #expect(once == twice)
    }

    // MARK: - Whitespace-only unclosed block reuse (see openBlock doc comment)

    /// Pinned trade-off: a whitespace-only UNCLOSED block between two other
    /// blocks is swallowed into the second, rather than surviving as a blank
    /// middle block the way a browser would render it. This is the accepted
    /// flip side of the empty-wrapper reuse fix — see `openBlock`'s doc
    /// comment. If this ever changes, it must be a deliberate decision.
    @Test func whitespaceOnlyUnclosedBlockIsSwallowedNotPreserved() {
        #expect(RichTextHTML.encode(RichTextHTML.decode("<p>a<p> <p>b"))
            == "<p>a</p>\n<p>b</p>")
    }

    // MARK: - Valid nested-list encoding (F6)

    //
    // A nested list belongs *inside* the preceding `<li>`, not as a direct
    // sibling of it. The decoder tolerates both forms (it already accepted
    // its own previously-invalid output), which is exactly why round-trip
    // tests alone can't catch this: both sides shared the same misconception.
    // These tests pin the *valid* form as a literal string on the encoder
    // side, and independently confirm the decoder reads the valid form into
    // the right depths.

    @Test func nestedListsEncodeAsValidHTML() {
        let doc = RichTextHTML.decode("<ul><li>a<ul><li>b</li></ul></li></ul>")
        #expect(RichTextHTML.encode(doc) == "<ul><li>a<ul><li>b</li></ul></li></ul>")
    }

    /// The decoder must read the *valid* nesting form, independently of what
    /// the encoder happens to emit.
    @Test func validNestedListDecodesToTheRightDepths() {
        let doc = RichTextHTML.decode("<ul><li>a<ul><li>b</li></ul></li></ul>")
        let roles = doc.runs.compactMap(\.blockStyle)
        #expect(roles.contains(.listItem(.unordered, depth: 0)))
        #expect(roles.contains(.listItem(.unordered, depth: 1)))
    }

    /// Three levels deep: each nested list nests inside the `<li>` above it.
    @Test func threeLevelsDeepEncodesAsValidHTML() {
        let doc = Sem.doc(
            Sem.block("a", .listItem(.unordered, depth: 0)),
            Sem.block("b", .listItem(.unordered, depth: 1)),
            Sem.block("c", .listItem(.unordered, depth: 2))
        )
        let html = RichTextHTML.encode(doc)
        #expect(html == "<ul><li>a<ul><li>b<ul><li>c</li></ul></li></ul></li></ul>")
        #expect(RichTextHTML.decode(html) == doc)
    }

    /// A nested list followed by a sibling at the outer level: the outer
    /// `<li>`'s close tag must land after the nested list closes, not before.
    @Test func nestedListFollowedByOuterSiblingClosesLiInTheRightPlace() {
        let doc = Sem.doc(
            Sem.block("a", .listItem(.unordered, depth: 0)),
            Sem.block("b", .listItem(.unordered, depth: 1)),
            Sem.block("c", .listItem(.unordered, depth: 0))
        )
        let html = RichTextHTML.encode(doc)
        #expect(html == "<ul><li>a<ul><li>b</li></ul></li><li>c</li></ul>")
        #expect(RichTextHTML.decode(html) == doc)
    }

    /// A list item at the same depth following a nested list (i.e. two
    /// siblings at depth 0 sandwiching a deeper item) must still separate
    /// correctly.
    @Test func listItemAfterNestedListAtSameDepth() {
        let doc = Sem.doc(
            Sem.block("a", .listItem(.unordered, depth: 0)),
            Sem.block("b", .listItem(.unordered, depth: 1)),
            Sem.block("c", .listItem(.unordered, depth: 1)),
            Sem.block("d", .listItem(.unordered, depth: 0))
        )
        let html = RichTextHTML.encode(doc)
        #expect(html == "<ul><li>a<ul><li>b</li><li>c</li></ul></li><li>d</li></ul>")
        #expect(RichTextHTML.decode(html) == doc)
    }

    /// Ordered nested inside unordered.
    @Test func orderedListNestedInsideUnorderedEncodesAsValidHTML() {
        let doc = Sem.doc(
            Sem.block("a", .listItem(.unordered, depth: 0)),
            Sem.block("b", .listItem(.ordered, depth: 1))
        )
        let html = RichTextHTML.encode(doc)
        #expect(html == "<ul><li>a<ol><li>b</li></ol></li></ul>")
        #expect(RichTextHTML.decode(html) == doc)
    }

    /// Unordered nested inside ordered.
    @Test func unorderedListNestedInsideOrderedEncodesAsValidHTML() {
        let doc = Sem.doc(
            Sem.block("a", .listItem(.ordered, depth: 0)),
            Sem.block("b", .listItem(.unordered, depth: 1))
        )
        let html = RichTextHTML.encode(doc)
        #expect(html == "<ol><li>a<ul><li>b</li></ul></li></ol>")
        #expect(RichTextHTML.decode(html) == doc)
    }

    /// Round-trip decode -> encode -> decode preserves block roles and depths
    /// for a valid deeply-nested, mixed-kind shape.
    @Test func deeplyNestedMixedKindListRoundTripsThroughDecodeEncodeDecode() {
        let html = "<ol><li>a<ul><li>b<ol><li>c</li></ol></li><li>d</li></ul></li><li>e</li></ol>"
        let decoded = RichTextHTML.decode(html)
        let reEncoded = RichTextHTML.encode(decoded)
        let redecoded = RichTextHTML.decode(reEncoded)
        #expect(redecoded == decoded)

        let roles = decoded.runs.compactMap(\.blockStyle)
        #expect(roles.contains(.listItem(.ordered, depth: 0)))
        #expect(roles.contains(.listItem(.unordered, depth: 1)))
        #expect(roles.contains(.listItem(.ordered, depth: 2)))
    }
}
