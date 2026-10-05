// HTMLEncoder.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation

/// Encodes a semantic `AttributedString` (block markers + inline attributes) into the canonical simple-HTML output.
enum HTMLEncoder {
    static func encode(_ attr: AttributedString) -> String {
        var lists = ListEmitter()
        for block in splitBlocks(attr) {
            let inline = inlineHTML(block.slice, in: attr)
            switch block.style {
            case let .listItem(kind, depth):
                lists.appendItem(kind: kind, depth: depth, inline: inline)
            case .paragraph:
                lists.closeAll()
                lists.segments.append("<p>\(inline)</p>")
            case let .heading(level):
                lists.closeAll()
                let clamped = min(max(level, 1), 3)
                lists.segments.append("<h\(clamped)>\(inline)</h\(clamped)>")
            case .blockquote:
                // A quote is a top-level block like <p>: it ends any open
                // list rather than nesting inside it, because the flat model
                // has no "quoted list item" role to have produced it.
                lists.closeAll()
                lists.segments.append("<blockquote>\(inline)</blockquote>")
            }
        }
        lists.closeAll()
        return lists.segments.joined(separator: "\n")
    }

    /// One open level of the list stack.
    ///
    /// `liOpen` tracks whether the most recently emitted `<li>` at this depth
    /// is still unclosed. A nested list belongs *inside* the preceding `<li>`,
    /// so that `<li>`'s closing tag must be deferred until either a sibling at
    /// the same depth arrives or the nested list is popped — never emitted
    /// eagerly, or the nested `<ul>`/`<ol>` would land as an invalid direct
    /// child of the outer list.
    private struct ListLevel {
        var kind: ListKind
        var depth: Int
        var liOpen: Bool
    }

    /// Accumulates top-level output units, joined with "\n". A run of
    /// consecutive list-item blocks (however deeply nested) forms a single
    /// unit with no internal separators between its open/li/close pieces.
    private struct ListEmitter {
        var segments: [String] = []
        private var buffer = ""
        private var stack: [ListLevel] = []

        mutating func appendItem(kind: ListKind, depth: Int, inline: String) {
            // close deeper/mismatched levels
            while let top = stack.last, top.depth > depth || (top.depth == depth && top.kind != kind) {
                closeTop()
            }
            // close the previous sibling's <li> at this depth, if still open
            if let top = stack.last, top.depth == depth, top.liOpen {
                buffer += "</li>"
                stack[stack.count - 1].liOpen = false
            }
            // open levels up to this depth. A level skipped on the way down
            // (a jump of more than one) still needs an `<li>` to hold the
            // next list, or that list lands as an invalid direct child of
            // this one. `display:block` keeps a browser
            // from drawing a marker for the placeholder or counting it, so
            // the rendered list matches the editor's. The decoder folds an
            // `<li>` that holds nothing but a nested list into the nested
            // item, so the placeholder adds no block on the way back.
            while stack.count <= depth {
                let openDepth = stack.count
                let isSkipped = openDepth < depth
                buffer += kind == .ordered ? "<ol>" : "<ul>"
                if isSkipped {
                    buffer += "<li style=\"display:block\">"
                }
                stack.append(ListLevel(kind: kind, depth: openDepth, liOpen: isSkipped))
            }
            buffer += "<li>\(inline)"
            stack[stack.count - 1].liOpen = true
        }

        mutating func closeAll() {
            while !stack.isEmpty {
                closeTop()
            }
            if !buffer.isEmpty {
                segments.append(buffer)
                buffer = ""
            }
        }

        private mutating func closeTop() {
            guard let top = stack.last else {
                return
            }
            if top.liOpen {
                buffer += "</li>"
            }
            buffer += top.kind == .ordered ? "</ol>" : "</ul>"
            stack.removeLast()
        }
    }

    private struct Block {
        var slice: Range<AttributedString.Index>
        var style: BlockStyle
    }

    private static func splitBlocks(_ attr: AttributedString) -> [Block] {
        var blocks: [Block] = []
        var start = attr.startIndex
        var index = attr.startIndex
        func pushBlock(end: AttributedString.Index) {
            // Defaults to .paragraph for an empty slice because Foundation can't
            // carry a blockStyle attribute on zero-length content; see the matching
            // note in `HTMLDecoder.Builder.finish()`.
            let style = (start < attr.endIndex) ? (attr[start ..< end].blockStyle ?? .paragraph) : .paragraph
            blocks.append(Block(slice: start ..< end, style: style))
        }
        while index < attr.endIndex {
            if attr.characters[index] == "\n" {
                pushBlock(end: index)
                start = attr.index(afterCharacter: index)
            }
            index = attr.index(afterCharacter: index)
        }
        pushBlock(end: attr.endIndex)
        for index in blocks.indices.dropFirst().dropLast() where blocks[index].slice.isEmpty {
            if let role = BlockStyle.roleOfEmptyBlock(between: blocks[index - 1].style, and: blocks[index + 1].style) {
                blocks[index].style = role
            }
        }
        return blocks
    }

    private static func inlineHTML(_ range: Range<AttributedString.Index>, in attr: AttributedString) -> String {
        var out = ""
        let sub = attr[range]
        for run in sub.runs {
            let runRange = run.range
            // U+2028 always stands alone as a grapheme cluster, so splitting on
            // the Character is safe; the escaping itself is scalar-based.
            let text = String(attr.characters[runRange])
                .split(separator: RichTextHTML.softLineBreak, omittingEmptySubsequences: false)
                .map { HTMLEscaping.escapeText(String($0)) }
                .joined(separator: "<br>")
            out += wrap(text, run: attr[runRange])
        }
        return out
    }

    private static func wrap(_ text: String, run: AttributedSubstring) -> String {
        var openTags = ""
        var closeTags = ""
        // Black is the absence of a text color everywhere in the system
        // (`RichTextColor.black`): the model treats them as identical, so a
        // run carrying black is not in canonical form and the encoder omits
        // the span rather than emitting `color:#000000`. This is not merely
        // defensive: `RichTextAttributes.TextColorKey` and the dynamic-member
        // subscript are public, so a caller can build `doc.textColor = .black`
        // and call `RichTextHTML.encode` directly — bypassing both the
        // command layer (`EngineCore+Inline`) and the decoder, the only two
        // places upstream that normalize it away. This check is what actually
        // guarantees black never reaches HTML output; see the precondition
        // this puts on `decode(encode(x)) == x` documented on
        // `RichTextHTML.encode`/`decode`.
        if let color = run.textColor, color != .black {
            openTags += "<span style=\"color:\(color.hexString)\">"
            closeTags = "</span>" + closeTags
        }
        if run.bold == true {
            openTags += "<b>"; closeTags = "</b>" + closeTags
        }
        if run.italic == true {
            openTags += "<i>"; closeTags = "</i>" + closeTags
        }
        if run.underline == true {
            openTags += "<u>"; closeTags = "</u>" + closeTags
        }
        if run.strikethrough == true {
            openTags += "<s>"; closeTags = "</s>" + closeTags
        }
        return openTags + text + closeTags
    }
}
