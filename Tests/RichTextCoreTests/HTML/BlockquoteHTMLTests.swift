// BlockquoteHTMLTests.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
@testable import RichTextCore
import Testing

/// F5: `<blockquote>` is a first-class semantic role, not an unknown-block
/// tag that degrades to `<p>`. Blockquote is authorable in the companion web
/// editor, so degrading it here is ongoing one-way data loss between two live
/// clients.
///
/// Every expectation below is a **literal** string or a literally-constructed
/// model — never a value computed by calling `encode`/`decode` on the other
/// side of the assertion. A round-trip assertion alone cannot catch an
/// encoder and a decoder that share the same misconception.
struct BlockquoteHTMLTests {
    // MARK: - Decode

    @Test func decodeBlockquoteProducesTheBlockquoteRole() {
        #expect(RichTextHTML.decode("<blockquote>quoted</blockquote>")
            == Sem.block("quoted", .blockquote))
    }

    @Test func decodeBlockquoteKeepsInlineFormatting() {
        var expected = Sem.block("quoted", .blockquote)
        expected.bold = true
        #expect(RichTextHTML.decode("<blockquote><b>quoted</b></blockquote>") == expected)
    }

    @Test func decodeBlockquoteWrappingAParagraphKeepsTheQuoteRole() {
        // `openBlock`'s wrapper-reuse rule keeps the more specific role: the
        // inner <p> must not demote the quote to a paragraph.
        #expect(RichTextHTML.decode("<blockquote><p>quoted</p></blockquote>")
            == Sem.block("quoted", .blockquote))
    }

    @Test func nestedBlockquotesFlattenToASingleQuote() {
        // The model is flat and `.blockquote` carries no depth (see the note
        // on `BlockStyle.blockquote`), so nesting collapses rather than being
        // silently half-represented.
        #expect(RichTextHTML.decode("<blockquote><blockquote>x</blockquote></blockquote>")
            == Sem.block("x", .blockquote))
    }

    @Test func aListInsideABlockquoteStaysAList() {
        // List membership is the more specific role and wins; the surrounding
        // quote is dropped rather than fabricating a quoted-list role the
        // flat model cannot express.
        #expect(RichTextHTML.decode("<blockquote><ul><li>a</li></ul></blockquote>")
            == Sem.block("a", .listItem(.unordered, depth: 0)))
    }

    @Test func aBlockquoteInsideAListItemStaysAListItem() {
        // The other direction of the same rule: list membership must win
        // regardless of which tag opens the shared empty block first. Before
        // the `specificity(of:)` ranking, the reuse rule in `openBlock`
        // treated "anything that is not `.paragraph`" as more specific,
        // so a <blockquote> opened *after* the <li> silently overrode the
        // list role — a regression this test pins against.
        #expect(RichTextHTML.decode("<ul><li><blockquote>x</blockquote></li></ul>")
            == Sem.block("x", .listItem(.unordered, depth: 0)))
    }

    @Test func multiParagraphBlockquoteKeepsTheQuoteRoleOnlyOnTheFirstBlock() {
        // KNOWN LIMITATION (GitHub issue #20):
        // the flat model holds one role per block and the decoder has no
        // quote-context stack, so a <blockquote> wrapping *multiple* blocks
        // only keeps the quote role on the first one — every subsequent
        // block silently reverts to `.paragraph`. This test pins today's
        // behavior so a future fix (adding a quote-context stack) shows up
        // as a deliberate, reviewed change rather than an accidental diff.
        let doc = RichTextHTML.decode("<blockquote><p>a</p><p>b</p></blockquote>")
        #expect(doc == Sem.doc(
            Sem.block("a", .blockquote),
            Sem.block("b", .paragraph)
        ))
    }

    // MARK: - Encode

    @Test func encodeBlockquoteEmitsABlockquoteElement() {
        #expect(RichTextHTML.encode(Sem.block("quoted", .blockquote))
            == "<blockquote>quoted</blockquote>")
    }

    @Test func encodeBlockquoteAmongOtherBlocks() {
        let doc = Sem.doc(
            Sem.block("Title", .heading(1)),
            Sem.block("quoted", .blockquote),
            Sem.block("after")
        )
        #expect(RichTextHTML.encode(doc)
            == "<h1>Title</h1>\n<blockquote>quoted</blockquote>\n<p>after</p>")
    }

    @Test func aBlockquoteClosesAnOpenList() {
        let doc = Sem.doc(
            Sem.block("a", .listItem(.unordered, depth: 0)),
            Sem.block("quoted", .blockquote)
        )
        #expect(RichTextHTML.encode(doc) == "<ul><li>a</li></ul>\n<blockquote>quoted</blockquote>")
    }

    // MARK: - Round trip

    @Test func blockquoteHTMLIsCanonicalAndIdempotent() {
        #expect(RichTextHTML.encode(RichTextHTML.decode("<blockquote>quoted</blockquote>"))
            == "<blockquote>quoted</blockquote>")
    }

    @Test func blockquoteModelRoundTripsThroughHTML() {
        let doc = Sem.doc(
            Sem.block("quoted", .blockquote),
            Sem.block("body")
        )
        #expect(RichTextHTML.decode(RichTextHTML.encode(doc)) == doc)
    }
}
