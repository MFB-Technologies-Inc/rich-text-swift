// HTMLListDepthJumpTests.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
@testable import RichTextCore
import Testing

/// A list item more than one level deeper than its predecessor (GitHub issue
/// #49). HTML only allows `<li>` as a child of `<ul>`/`<ol>`, so every skipped
/// level must still open inside an `<li>` of its own, never as a bare list
/// directly inside a list. That placeholder is `display:block` so a browser
/// neither draws a marker for it nor counts it, matching the editor.
struct HTMLListDepthJumpTests {
    /// Every tag pair that puts a list directly inside a list: a list open
    /// right after another list open, or right after a sibling `</li>`.
    private static let listInsideListPairs = [
        "<ol><ol>", "<ul><ul>", "<ol><ul>", "<ul><ol>",
        "</li><ol>", "</li><ul>",
    ]

    private static func listInsideListPairs(in html: String) -> [String] {
        listInsideListPairs.filter { html.contains($0) }
    }

    @Test func orderedJumpOfTwoLevelsNestsTheSkippedLevelInAnItem() {
        let doc = Sem.doc(
            Sem.block("a", .listItem(.ordered, depth: 0)),
            Sem.block("b", .listItem(.ordered, depth: 2))
        )
        #expect(
            RichTextHTML.encode(doc)
                == #"<ol><li>a<ol><li style="display:block"><ol><li>b</li></ol></li></ol></li></ol>"#
        )
    }

    @Test func unorderedJumpOfTwoLevelsNestsTheSkippedLevelInAnItem() {
        let doc = Sem.doc(
            Sem.block("a", .listItem(.unordered, depth: 0)),
            Sem.block("b", .listItem(.unordered, depth: 2))
        )
        #expect(
            RichTextHTML.encode(doc)
                == #"<ul><li>a<ul><li style="display:block"><ul><li>b</li></ul></li></ul></li></ul>"#
        )
    }

    @Test func firstItemAtDepthTwoOpensAnItemForEachSkippedLevel() {
        let doc = Sem.block("text0", .listItem(.ordered, depth: 2))
        #expect(
            RichTextHTML.encode(doc)
                == #"<ol><li style="display:block"><ol><li style="display:block">"#
                + "<ol><li>text0</li></ol></li></ol></li></ol>"
        )
    }

    /// The skipped level takes the kind of the item that skipped it, and a
    /// later item back at that depth with the other kind closes it and opens
    /// its own list, still inside the depth-0 item.
    @Test func mixedKindJumpThenReturnToTheSkippedDepth() {
        let doc = Sem.doc(
            Sem.block("a", .listItem(.unordered, depth: 0)),
            Sem.block("b", .listItem(.ordered, depth: 2)),
            Sem.block("c", .listItem(.unordered, depth: 1))
        )
        #expect(
            RichTextHTML.encode(doc)
                == #"<ul><li>a<ol><li style="display:block"><ol><li>b</li></ol></li></ol><ul><li>c</li></ul></li></ul>"#
        )
    }

    /// A sibling at the skipped depth closes the placeholder item and opens a
    /// real one next to it.
    @Test func siblingAtTheSkippedDepthFollowsThePlaceholderItem() {
        let doc = Sem.doc(
            Sem.block("a", .listItem(.ordered, depth: 0)),
            Sem.block("b", .listItem(.ordered, depth: 2)),
            Sem.block("c", .listItem(.ordered, depth: 1))
        )
        #expect(
            RichTextHTML.encode(doc)
                == #"<ol><li>a<ol><li style="display:block"><ol><li>b</li></ol></li><li>c</li></ol></li></ol>"#
        )
    }

    /// An `<li>` that holds nothing but a nested list is the placeholder for
    /// a skipped level: it produces no block, and the nested item keeps its
    /// own depth rather than inheriting the placeholder's.
    @Test func decodingAnItemThatOnlyHoldsANestedListKeepsTheInnerDepth() {
        let html = "<ul><li><ul><li>b</li></ul></li></ul>"
        #expect(RichTextHTML.decode(html) == Sem.block("b", .listItem(.unordered, depth: 1)))
    }

    /// The encoder's own placeholder decodes the same way: its `style` is
    /// presentation only.
    @Test func decodingTheEncodersPlaceholderKeepsTheInnerDepth() {
        let html = #"<ul><li style="display:block"><ul><li>b</li></ul></li></ul>"#
        #expect(RichTextHTML.decode(html) == Sem.block("b", .listItem(.unordered, depth: 1)))
    }

    static let depthJumpDocuments: [AttributedString] = [
        Sem.doc(
            Sem.block("a", .listItem(.ordered, depth: 0)),
            Sem.block("b", .listItem(.ordered, depth: 2))
        ),
        Sem.doc(
            Sem.block("a", .listItem(.unordered, depth: 0)),
            Sem.block("b", .listItem(.unordered, depth: 3))
        ),
        Sem.block("text0", .listItem(.ordered, depth: 2)),
        Sem.block("text0", .listItem(.unordered, depth: 3)),
        Sem.doc(
            Sem.block("a", .listItem(.unordered, depth: 0)),
            Sem.block("b", .listItem(.ordered, depth: 2)),
            Sem.block("c", .listItem(.unordered, depth: 1))
        ),
        Sem.doc(
            Sem.block("a", .listItem(.ordered, depth: 0)),
            Sem.block("b", .listItem(.unordered, depth: 3)),
            Sem.block("c", .listItem(.ordered, depth: 1)),
            Sem.block("d", .listItem(.unordered, depth: 0))
        ),
        Sem.doc(
            Sem.block("Title", .heading(1)),
            Sem.block("a", .listItem(.ordered, depth: 2)),
            Sem.block("Body"),
            Sem.block("b", .listItem(.unordered, depth: 1))
        ),
    ]

    /// Parameterized by index, not by document: a test case's ID comes from the
    /// argument's Codable encoding, which drops the block-role attributes, so
    /// documents that differ only in list kind or depth share an ID. `swift test`
    /// tolerates that, but xcodebuild's XCTest harness crashes on it.
    @Test(arguments: depthJumpDocuments.indices)
    func depthJumpNeverEmitsAListDirectlyInsideAList(_ index: Int) {
        let html = RichTextHTML.encode(Self.depthJumpDocuments[index])
        #expect(Self.listInsideListPairs(in: html).isEmpty, "\(html)")
    }

    @Test(arguments: depthJumpDocuments.indices)
    func depthJumpRoundTripsExactly(_ index: Int) {
        let doc = Self.depthJumpDocuments[index]
        #expect(RichTextHTML.decode(RichTextHTML.encode(doc)) == doc)
    }
}
