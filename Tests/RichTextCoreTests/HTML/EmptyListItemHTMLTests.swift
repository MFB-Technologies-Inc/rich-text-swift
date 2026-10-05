// EmptyListItemHTMLTests.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
@testable import RichTextCore
import Testing

/// An empty block between two items of the same list is an empty item of
/// that list, not a paragraph that splits it (GitHub issue #74). An empty
/// block can't carry a role of its own (D13), so the role comes from the
/// items around it.
struct EmptyListItemHTMLTests {
    private let one = BlockStyle.listItem(.ordered, depth: 0)

    @Test func anEmptyBlockBetweenItemsOfOneListIsAnEmptyItem() {
        let doc = Sem.doc(Sem.block("a", one), Sem.block(""), Sem.block("c", one))
        #expect(RichTextHTML.encode(doc) == "<ol><li>a</li><li></li><li>c</li></ol>")
        #expect(RichTextHTML.decode(RichTextHTML.encode(doc)) == doc)
    }

    @Test func anEmptyItemLoadsAndSavesUnchanged() {
        for html in [
            "<ol><li>a</li><li></li><li>c</li></ol>",
            "<ul><li>a<ul><li>b</li><li></li><li>d</li></ul></li></ul>",
        ] {
            #expect(RichTextHTML.encode(RichTextHTML.decode(html)) == html)
        }
    }

    @Test func anEmptyBlockBetweenDifferentListsStillSplitsThem() {
        let doc = Sem.doc(
            Sem.block("a", .listItem(.unordered, depth: 0)),
            Sem.block(""),
            Sem.block("b", one)
        )
        #expect(RichTextHTML.encode(doc) == "<ul><li>a</li></ul>\n<p></p>\n<ol><li>b</li></ol>")
    }

    @Test func anEmptyBlockBetweenDifferentDepthsIsNotAnItem() {
        let doc = Sem.doc(
            Sem.block("a", one),
            Sem.block(""),
            Sem.block("b", .listItem(.ordered, depth: 1))
        )
        #expect(RichTextHTML.encode(doc).contains("<p></p>"))
    }

    @Test func anEmptyBlockAtEitherEndOfAListIsAParagraph() {
        #expect(RichTextHTML.encode(Sem.doc(Sem.block("a", one), Sem.block(""))) == "<ol><li>a</li></ol>\n<p></p>")
        #expect(RichTextHTML.encode(Sem.doc(Sem.block(""), Sem.block("a", one))) == "<p></p>\n<ol><li>a</li></ol>")
    }

    @Test func twoEmptyBlocksBetweenItemsSplitTheList() {
        let doc = Sem.doc(Sem.block("a", one), Sem.block(""), Sem.block(""), Sem.block("b", one))
        #expect(RichTextHTML.encode(doc) == "<ol><li>a</li></ol>\n<p></p>\n<p></p>\n<ol><li>b</li></ol>")
    }
}
