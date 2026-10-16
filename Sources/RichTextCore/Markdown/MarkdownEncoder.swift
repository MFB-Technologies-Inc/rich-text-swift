// MarkdownEncoder.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation

/// Encodes a semantic `AttributedString` into canonical Markdown: a blank line
/// between blocks, and list items tight.
enum MarkdownEncoder {
    /// One open level of the list stack: the current item's kind, number and
    /// marker width, which is how far its children are indented.
    private struct ListLevel {
        var kind: ListKind
        var number: Int
        var markerWidth: Int
    }

    static func encode(_ attr: AttributedString) -> String {
        var out = ""
        var lists: [ListLevel] = []
        var previousWasListItem = false
        // Markdown can't hold an empty block, so empty blocks are skipped.
        for block in DocumentBlocks.split(attr) where !block.slice.isEmpty {
            let content = attr[block.slice]
            var isListItem = false
            let text: String
            switch block.style {
            case .paragraph:
                text = MarkdownInlineEncoder.encode(content, heading: false, continuation: "")
            case let .heading(level):
                let hashes = String(repeating: "#", count: min(max(level, 1), 3))
                text = hashes + " " + MarkdownInlineEncoder.encode(content, heading: true, continuation: "")
            case .blockquote:
                text = "> " + MarkdownInlineEncoder.encode(content, heading: false, continuation: "> ")
            case let .listItem(kind, depth):
                isListItem = true
                text = listItem(content, kind: kind, depth: depth, lists: &lists)
            }
            if !isListItem {
                lists.removeAll()
            }
            if !out.isEmpty {
                out += previousWasListItem && isListItem ? "\n" : "\n\n"
            }
            out += text
            previousWasListItem = isListItem
        }
        return out
    }

    /// One list item. A child list is indented by its ancestors' marker
    /// widths (`- ` is 2, `1. ` is 3, `10. ` is 4). A level skipped on the way
    /// down gets a placeholder item holding only the next marker, on the same
    /// line (`- - c`): a placeholder on a line of its own would be dropped as
    /// an empty item, or read as a setext underline.
    private static func listItem(
        _ content: AttributedSubstring,
        kind: ListKind,
        depth: Int,
        lists: inout [ListLevel]
    ) -> String {
        if lists.count > depth + 1 {
            lists.removeLast(lists.count - depth - 1)
        }
        // A different kind at the same depth starts a new list.
        if lists.count == depth + 1, lists[depth].kind != kind {
            lists.removeLast()
        }
        let indent = lists.prefix(depth).reduce(0) { $0 + $1.markerWidth }
        var markers = ""
        while lists.count < depth {
            let placeholder = marker(kind, number: 1)
            lists.append(ListLevel(kind: kind, number: 1, markerWidth: placeholder.count))
            markers += placeholder
        }
        if lists.count == depth {
            lists.append(ListLevel(kind: kind, number: 0, markerWidth: 0))
        }
        lists[depth].number += 1
        let own = marker(kind, number: lists[depth].number)
        lists[depth].markerWidth = own.count
        markers += own
        let continuation = String(repeating: " ", count: indent + markers.count)
        return String(repeating: " ", count: indent) + markers
            + MarkdownInlineEncoder.encode(content, heading: false, continuation: continuation)
    }

    private static func marker(_ kind: ListKind, number: Int) -> String {
        kind == .ordered ? "\(number). " : "- "
    }
}
