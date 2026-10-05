// BlockScannerHTMLParityTests.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
import RichTextCore
@testable import RichTextEngine
import Testing

/// Pins M3 decision D11's cross-layer requirement: `BlockScanner`'s block
/// splitting must agree exactly with `HTMLEncoder.splitBlocks`. The two are
/// independent implementations (different files, differently-written
/// empty-slice guards) with no shared code, so nothing *forces* them to
/// agree — only a test can.
///
/// `HTMLEncoder.splitBlocks` is private, so this can't call it directly.
/// Instead it reconstructs, from `RichTextHTML.encode`'s own output string,
/// the same (style, text) sequence the encoder must have derived internally
/// to produce that output — using a small test-only parser tailored to the
/// canonical simple-HTML grammar (dev-plan: `<p>`, `<h1-3>`, and possibly-
/// nested `<ul>`/`<ol>`/`<li>` groups, joined by bare `"\n"` at the top
/// level, with `<b>/<i>/<u>/<s>/<span style="color:...">` inline markup and
/// `&amp;/&lt;/&gt;`/`<br>` escaping). That sequence is then compared against
/// `BlockScanner.blocks(of:)` read off the *same* original document. Any
/// genuine disagreement between the two implementations — different block
/// count, different style, different text — fails this test.
struct BlockScannerHTMLParityTests {
    private struct ParsedBlock: Equatable, CustomStringConvertible {
        var style: BlockStyle
        var text: String
        var description: String {
            "\(style): \(text.debugDescription)"
        }
    }

    // MARK: - The test-only HTML structural parser

    private func parseCanonicalHTML(_ html: String) -> [ParsedBlock] {
        html.components(separatedBy: "\n").flatMap(parseSegment)
    }

    private func parseSegment(_ segment: String) -> [ParsedBlock] {
        if segment.hasPrefix("<p>"), segment.hasSuffix("</p>") {
            let inner = String(segment.dropFirst("<p>".count).dropLast("</p>".count))
            return [ParsedBlock(style: .paragraph, text: plainText(inner))]
        }
        if segment.hasPrefix("<blockquote>"), segment.hasSuffix("</blockquote>") {
            let inner = String(segment.dropFirst("<blockquote>".count).dropLast("</blockquote>".count))
            return [ParsedBlock(style: .blockquote, text: plainText(inner))]
        }
        for level in 1 ... 3 {
            let open = "<h\(level)>"
            let close = "</h\(level)>"
            if segment.hasPrefix(open), segment.hasSuffix(close) {
                let inner = String(segment.dropFirst(open.count).dropLast(close.count))
                return [ParsedBlock(style: .heading(level), text: plainText(inner))]
            }
        }
        return parseListGroup(segment)
    }

    /// A run of (possibly nested) `<ul>`/`<ol>`/`<li>` tags with no
    /// separators between them, exactly as `HTMLEncoder` emits one. A nested
    /// list is emitted *inside* the preceding `<li>`, before that `<li>`'s
    /// own closing tag (F6: the encoder used to emit it as a sibling of the
    /// `<li>`, which is invalid HTML — fixed so nesting is valid). So each
    /// `<li>`'s content ends at whichever comes first: its `</li>`, or a
    /// nested `<ul>`/`<ol>` opening inside it; a recursive-descent parser
    /// mirrors that shape directly, using `depth` (the recursion depth)
    /// rather than a flat stack.
    private func parseListGroup(_ segment: String) -> [ParsedBlock] {
        var blocks: [ParsedBlock] = []
        var index = segment.startIndex
        // A segment can hold more than one complete top-level list back to
        // back: a kind change at depth 0 (e.g. <ul>...</ul> followed by
        // <ol>...</ol>) closes and reopens without a flushed separator, so
        // this loops rather than parsing just one.
        while index < segment.endIndex {
            guard parseList(segment, &index, depth: 0, into: &blocks) else { return blocks }
        }
        return blocks
    }

    private func match(_ segment: String, _ index: inout String.Index, _ tag: String) -> Bool {
        guard segment[index...].hasPrefix(tag) else { return false }
        index = segment.index(index, offsetBy: tag.count)
        return true
    }

    private func peekingListOpen(_ segment: String, _ index: String.Index) -> Bool {
        segment[index...].hasPrefix("<ul>") || segment[index...].hasPrefix("<ol>")
    }

    private struct TagMatch { var tag: String; var range: Range<String.Index> }

    /// The earliest occurrence, from `index` onward, of any tag in `tags`.
    private func earliestOf(_ segment: String, from index: String.Index, tags: [String]) -> TagMatch? {
        var best: TagMatch?
        for tag in tags {
            if let range = segment.range(of: tag, range: index ..< segment.endIndex),
               best == nil || range.lowerBound < best!.range.lowerBound
            {
                best = TagMatch(tag: tag, range: range)
            }
        }
        return best
    }

    /// Parses one `<ul>...</ul>` / `<ol>...</ol>` list at `depth`, appending
    /// its `<li>` items — and, recursively, any list nested inside one of
    /// them at `depth + 1` — to `blocks`. Returns `false` (after recording an
    /// `Issue`) if `segment` isn't shaped like a list starting at `index`.
    private func parseList(
        _ segment: String,
        _ index: inout String.Index,
        depth: Int,
        into blocks: inout [ParsedBlock]
    ) -> Bool {
        let kind: ListKind
        if match(segment, &index, "<ul>") {
            kind = .unordered
        } else if match(segment, &index, "<ol>") {
            kind = .ordered
        } else {
            Issue.record("Expected <ul> or <ol> in segment: \(segment)")
            return false
        }
        let closeTag = kind == .ordered ? "</ol>" : "</ul>"

        while !match(segment, &index, closeTag) {
            // The placeholder `HTMLEncoder` opens for a level skipped by a
            // depth jump (GitHub issue #49) is the only `<li>` it gives an
            // attribute.
            let isPlaceholderTag = match(segment, &index, #"<li style="display:block">"#)
            guard isPlaceholderTag || match(segment, &index, "<li>") else {
                Issue.record("Expected <li> or \(closeTag) in segment: \(segment)")
                return false
            }
            guard let stop = earliestOf(segment, from: index, tags: ["</li>", "<ul>", "<ol>"]) else {
                Issue.record("Malformed <li> with no matching </li> in segment: \(segment)")
                return false
            }
            let text = String(segment[index ..< stop.range.lowerBound])
            let item = ParsedBlock(style: .listItem(kind, depth: depth), text: plainText(text))
            guard record(item, isPlaceholder: isPlaceholderTag, stop: stop, segment, into: &blocks)
            else { return false }
            index = stop.range.lowerBound

            if stop.tag == "</li>" {
                index = stop.range.upperBound
            } else {
                // A single <li> can hold a *run* of sibling nested lists —
                // e.g. a kind change at depth+1 closes one nested list and
                // opens another, both still inside this <li> — not just
                // one, so keep recursing into nested lists as long as
                // another <ul>/<ol> open follows, and only then require the
                // </li>.
                repeat {
                    guard parseList(segment, &index, depth: depth + 1, into: &blocks) else { return false }
                } while peekingListOpen(segment, index)
                guard match(segment, &index, "</li>") else {
                    Issue.record("Expected </li> after nested list(s) in segment: \(segment)")
                    return false
                }
            }
        }
        return true
    }

    /// Appends `item` to `blocks`, unless its `<li>` is a placeholder. A
    /// placeholder is not a block: it holds nothing but the nested list for
    /// the next level down, and anything else in it is a failure.
    private func record(
        _ item: ParsedBlock,
        isPlaceholder: Bool,
        stop: TagMatch,
        _ segment: String,
        into blocks: inout [ParsedBlock]
    ) -> Bool {
        guard isPlaceholder else {
            blocks.append(item)
            return true
        }
        guard item.text.isEmpty, stop.tag != "</li>" else {
            Issue.record("Placeholder <li> must hold only a nested list in segment: \(segment)")
            return false
        }
        return true
    }

    /// Strips inline markup and undoes `HTMLEncoder`'s escaping, leaving the
    /// plain characters a block's text run(s) actually held.
    private func plainText(_ inner: String) -> String {
        var text = inner
        for tag in ["<b>", "</b>", "<i>", "</i>", "<u>", "</u>", "<s>", "</s>", "</span>"] {
            text = text.replacingOccurrences(of: tag, with: "")
        }
        while let openStart = text.range(of: "<span"), let tagEnd = text.range(
            of: ">",
            range: openStart.lowerBound ..< text.endIndex
        ) {
            text.removeSubrange(openStart.lowerBound ..< tagEnd.upperBound)
        }
        text = text.replacingOccurrences(of: "<br>", with: String(RichTextHTML.softLineBreak))
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        return text
    }

    // MARK: - The BlockScanner side

    private func expectedBlocks(of doc: AttributedString) -> [ParsedBlock] {
        BlockScanner.blocks(of: doc).map { block in
            let range = TextOffsets.range(TextSelection(location: block.location, length: block.length), in: doc)
            return ParsedBlock(style: block.style, text: String(doc[range].characters))
        }
    }

    private func assertParity(_ doc: AttributedString) {
        let expected = expectedBlocks(of: doc)
        let html = RichTextHTML.encode(doc)
        let actual = parseCanonicalHTML(html)
        #expect(actual == expected, "encode() output: \(html.debugDescription)")
    }

    // MARK: - Spread of shapes

    @Test func singleBlock() {
        assertParity(Sem.block("Hello"))
    }

    @Test func singleHeadingBlock() {
        assertParity(Sem.block("Title", .heading(2)))
    }

    @Test func blockquoteBlock() {
        assertParity(Sem.block("quoted", .blockquote))
    }

    @Test func blockquoteBetweenAListAndAParagraph() {
        assertParity(Sem.doc(
            Sem.block("a", .listItem(.unordered, depth: 0)),
            Sem.block("quoted", .blockquote),
            Sem.block("after")
        ))
    }

    @Test func multipleBlocks() {
        assertParity(Sem.doc(Sem.block("First"), Sem.block("Second"), Sem.block("Third")))
    }

    @Test func emptyDocument() {
        assertParity(AttributedString(""))
    }

    @Test func leadingEmptyBlock() {
        assertParity(Sem.doc(Sem.block(""), Sem.block("abc")))
    }

    @Test func middleEmptyBlock() {
        assertParity(Sem.doc(Sem.block("abc"), Sem.block(""), Sem.block("def")))
    }

    @Test func trailingEmptyBlock() {
        assertParity(Sem.doc(Sem.block("abc"), Sem.block("")))
    }

    @Test func consecutiveEmptyBlocks() {
        assertParity(Sem.doc(Sem.block("abc"), Sem.block(""), Sem.block(""), Sem.block("def")))
    }

    @Test func onlyEmptyBlocks() {
        assertParity(Sem.doc(Sem.block(""), Sem.block(""), Sem.block("")))
    }

    @Test func headingsAndNestedListItems() {
        assertParity(Sem.doc(
            Sem.block("Title", .heading(1)),
            Sem.block("One", .listItem(.unordered, depth: 0)),
            Sem.block("Two", .listItem(.unordered, depth: 1)),
            Sem.block("Three", .listItem(.ordered, depth: 2)),
            Sem.block("Four", .listItem(.unordered, depth: 0)),
            Sem.block("Body", .heading(3))
        ))
    }

    /// A single `<li>` can legitimately hold a *run* of sibling nested lists
    /// of different kinds (not just one) before its own `</li>`: depth 0
    /// "a", then depth-1 unordered "b", then depth-1 *ordered* "c" — the
    /// kind change at depth 1 closes the unordered nested list and opens an
    /// ordered one, both still inside "a"'s `<li>`, before depth drops back
    /// to 0 for "d". Pins the parity harness's own generality (found via a
    /// brute-force sweep over `roleRoster`, not the fixed cyclic sweep
    /// below, which happens not to generate this shape).
    @Test func siblingNestedListsOfDifferentKindsInsideOneListItem() {
        assertParity(Sem.doc(
            Sem.block("a", .listItem(.unordered, depth: 0)),
            Sem.block("b", .listItem(.unordered, depth: 1)),
            Sem.block("c", .listItem(.ordered, depth: 1)),
            Sem.block("d", .listItem(.unordered, depth: 0))
        ))
    }

    @Test func mixedListKindsAtTheSameDepthForceASplit() {
        assertParity(Sem.doc(
            Sem.block("a", .listItem(.unordered, depth: 0)),
            Sem.block("b", .listItem(.ordered, depth: 0)),
            Sem.block("c", .listItem(.unordered, depth: 0))
        ))
    }

    @Test func multiUTF16CharactersAdjacentToNewlines() {
        // Emoji are 2 UTF-16 units each; place them right at block edges.
        assertParity(Sem.doc(Sem.block("a🙂"), Sem.block("🙂b"), Sem.block("")))
        assertParity(Sem.doc(Sem.block("🙂"), Sem.block("🙂"), Sem.block("c🙂d")))
    }

    @Test func inlineAttributesAndEscapedCharactersAlongsideBlockStructure() {
        var doc = Sem.doc(
            Sem.with(Sem.block("a&b<c>d", .heading(1)), bold: true),
            Sem.block("plain"),
            Sem.block("x", .listItem(.unordered, depth: 0))
        )
        doc[TextOffsets.range(TextSelection(location: 0, length: 1), in: doc)].italic = true
        assertParity(doc)
    }

    // MARK: - Deterministic generated sweep (Fix 4)

    //
    // Index-derived, not random: for each `i` in a fixed range, builds a
    // fixed-length document whose block roles cycle through a fixed roster
    // (offset by `i`) with a deterministic subset of blocks forced empty.
    // Same inputs every run.

    private static let roleRoster: [BlockStyle] = [
        .paragraph,
        .heading(1),
        .heading(2),
        .heading(3),
        .listItem(.unordered, depth: 0),
        .listItem(.unordered, depth: 1),
        .listItem(.ordered, depth: 0),
        .listItem(.ordered, depth: 2),
    ]

    @Test func deterministicSweepOverRolesAndEmptiness() {
        let blockCount = 4
        for i in 0 ..< Self.roleRoster.count {
            var blocks: [AttributedString] = []
            for j in 0 ..< blockCount {
                let role = Self.roleRoster[(i + j) % Self.roleRoster.count]
                // Deterministically force every third block (by combined
                // index) empty — exercises empty blocks at leading, middle,
                // and trailing positions across the sweep without random input.
                let isEmpty = (i + j) % 3 == 0
                blocks.append(Sem.block(isEmpty ? "" : "text\(j)", role))
            }
            let doc = Sem.doc(blocks[0], blocks[1], blocks[2], blocks[3])
            assertParity(doc)
        }
    }
}
