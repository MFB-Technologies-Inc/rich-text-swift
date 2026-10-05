// HTMLUnclosedSkipTagTests.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
@testable import RichTextCore
import Testing

/// A skip element (`<script>`, `<svg>`, `<head>`, …) with no end tag is
/// ignored: its start tag is dropped and its content decodes as ordinary
/// content, so it can't swallow the rest of the document (GitHub issue #52).
struct HTMLUnclosedSkipTagTests {
    private func roundTrip(_ html: String) -> String {
        RichTextHTML.encode(RichTextHTML.decode(html))
    }

    @Test func unclosedSkipTagIsIgnoredAndItsContentKept() {
        #expect(roundTrip("<p>a <svg data=x> keep me</p><p>and this</p>") == "<p>a keep me</p>\n<p>and this</p>")
        #expect(roundTrip("<p>a <script>run()</p><p>b</p>") == "<p>a run()</p>\n<p>b</p>")
    }

    @Test func unclosedSkipTagInAListItemKeepsTheFollowingItems() {
        #expect(roundTrip("<ul><li>a<svg>x</li><li>b</li></ul>") == "<ul><li>ax</li><li>b</li></ul>")
    }

    /// End tags pair with the nearest unmatched start tag of the same name,
    /// so with one `</svg>` for two `<svg>`s it's the outer one that's unclosed.
    @Test func nestedSkipTagsPairInnermostFirst() {
        #expect(roundTrip("<p>a<svg>b<svg>hidden</svg>c</p><p>d</p>") == "<p>abc</p>\n<p>d</p>")
    }

    /// A later, well-formed element of the same name keeps its own end tag, so
    /// the unclosed one can't borrow it and hide the blocks in between.
    @Test func unclosedSkipTagDoesNotBorrowALaterElementsEndTag() {
        let html = "<p>a<svg>broken</p><p>real</p><svg>icon</svg><p>c</p>"
        #expect(roundTrip(html) == "<p>abroken</p>\n<p>real</p>\n<p>c</p>")
    }

    // MARK: - Raw-text elements

    /// Tags inside a script are text, so a `"</svg>"` string can't close an
    /// earlier unclosed `<svg>` and hide the blocks in between.
    @Test func endTagStringInsideALaterScriptDoesNotCloseAnUnclosedSkipTag() {
        let html = "<p>a<svg>b</p><p>c</p><script>s=\"</svg>\";t()</script><p>d</p>"
        #expect(roundTrip(html) == "<p>ab</p>\n<p>c</p>\n<p>d</p>")
    }

    /// A `"<script>"` string inside a script doesn't nest: the script ends at
    /// the first `</script>`, as in a browser.
    @Test func startTagStringInsideAScriptDoesNotNest() {
        #expect(roundTrip("<script>document.write(\"<script>x\")</script><p>ok</p>") == "<p>ok</p>")
    }

    /// Like a browser, a script with no end tag of its own runs to the next
    /// `</script>`, even one that belongs to a later script.
    @Test func unclosedScriptRunsToTheNextScriptEndTag() {
        let html = "<p>a<script>broken()</p><p>real</p><script>ok()</script><p>c</p>"
        #expect(roundTrip(html) == "<p>a</p>\n<p>c</p>")
    }

    /// `</head>` is optional in HTML, so a document that leaves it out must
    /// keep its body (GitHub issue #65).
    @Test func headWithoutAnEndTagKeepsTheBody() {
        let html = "<html><head><title>T</title><style>p{}</style><body><p>hi</p></body></html>"
        #expect(roundTrip(html) == "<p>hi</p>")
    }

    // MARK: - Closed skip elements are unchanged

    @Test func closedSkipElementsStillHideTheirContent() {
        #expect(roundTrip("<p>a<svg><g><text>label</text></g></svg> b</p>") == "<p>a b</p>")
        #expect(roundTrip("<template><div>hidden</div></template><p>ok</p>") == "<p>ok</p>")
        #expect(roundTrip("<svg>a<svg>b</svg>c</svg><p>ok</p>") == "<p>ok</p>")
    }

    /// Only a skip element's own end tag ends it, so tag-like strings in a
    /// well-formed script or stylesheet stay hidden.
    @Test func endTagStringsInsideAClosedScriptOrStyleStayHidden() {
        #expect(roundTrip("<p>a</p><script>x = \"</p>\"; y()</script><p>b</p>") == "<p>a</p>\n<p>b</p>")
        #expect(roundTrip("<style>/* </div> */ p{}</style><p>b</p>") == "<p>b</p>")
    }

    // MARK: - Sweep

    private static let skipTags = HTMLTagClasses.skipContent.subtracting(HTMLTagClasses.void).sorted()

    /// Each block as (opening markup, closing markup) around its text.
    private static let blockShapes: [(open: String, close: String)] = [
        ("<p>", "</p>"),
        ("<h1>", "</h1>"),
        ("<h3>", "</h3>"),
        ("<blockquote>", "</blockquote>"),
        ("<div>", "</div>"),
        ("<ul><li>", "</li></ul>"),
        ("<ol><li>", "</li></ol>"),
    ]

    /// For every skip tag, block kind and position in a three-block document:
    /// an unclosed skip element decodes as if only its start tag were missing,
    /// and a closed one as if it weren't there at all.
    @Test(arguments: skipTags)
    func unclosedSkipTagIsDroppedAndClosedOneIsHidden(_ tag: String) {
        for shape in Self.blockShapes {
            for target in 0 ..< 3 {
                func document(injecting injection: String) -> String {
                    (0 ..< 3).map { index in
                        let extra = index == target ? injection : ""
                        return shape.open + "block \(index)" + extra + shape.close
                    }.joined()
                }
                let unclosed = RichTextHTML.decode(document(injecting: "<\(tag)> content"))
                let closed = RichTextHTML.decode(document(injecting: "<\(tag)> content</\(tag)>"))
                #expect(
                    unclosed == RichTextHTML.decode(document(injecting: " content")),
                    "unclosed <\(tag)> in block \(target) of \(shape.open)"
                )
                #expect(
                    closed == RichTextHTML.decode(document(injecting: "")),
                    "closed <\(tag)> in block \(target) of \(shape.open)"
                )
            }
        }
    }
}
