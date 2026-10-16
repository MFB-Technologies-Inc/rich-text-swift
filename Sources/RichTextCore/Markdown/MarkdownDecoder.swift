// MarkdownDecoder.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation

/// Decodes Markdown into the semantic model. Foundation's parser does the
/// parsing; this maps its presentation intents onto `BlockStyle` and the
/// inline keys, keeping the text of anything the model can't hold yet.
enum MarkdownDecoder {
    static func decode(_ markdown: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        var builder = Builder()
        guard let parsed = try? AttributedString(markdown: markdown, options: options) else {
            // `.returnPartiallyParsedIfPossible` makes this unreachable in
            // practice; if parsing fails anyway, keep the text.
            for line in markdown.split(separator: "\n") {
                builder.appendParagraph(String(line))
            }
            return builder.finish()
        }
        for run in parsed.runs {
            builder.add(
                String(parsed[run.range].characters),
                components: run.presentationIntent?.components ?? [],
                inline: run.inlinePresentationIntent ?? []
            )
        }
        return builder.finish()
    }

    private struct Block {
        enum Kind {
            case text
            /// One paragraph per line.
            case code
            /// Raw HTML source, decoded with `RichTextHTML`.
            case html
        }

        /// The parser's identity for the block this text belongs to, so runs
        /// of one paragraph (or one table row) join into one model block.
        var key: Int?
        var style: BlockStyle
        var kind: Kind
        var text: AttributedString
    }

    private struct Builder {
        private var blocks: [Block] = []
        private var lastCell: Int?

        mutating func add(
            _ text: String,
            components: [PresentationIntent.IntentType],
            inline: InlinePresentationIntent
        ) {
            // A rule has no text the model could hold, and inline HTML is
            // markup rather than text (this also drops the encoder's
            // `<!-- -->` separator). An HTML *block* may hold text, so it is
            // kept for `finish()` to decode.
            if components.contains(where: { $0.kind == .thematicBreak }) || inline.contains(.inlineHTML) {
                return
            }
            var piece = AttributedString(inline.contains(.lineBreak) ? String(RichTextHTML.softLineBreak) : text)
            if inline.contains(.stronglyEmphasized) {
                piece.bold = true
            }
            if inline.contains(.emphasized) {
                piece.italic = true
            }
            if inline.contains(.strikethrough) {
                piece.strikethrough = true
            }

            let row = components.first { $0.kind == .tableHeaderRow || Self.isTableRow($0.kind) }
            let key = row?.identity ?? components.first?.identity
            let cell = components.first { Self.isTableCell($0.kind) }?.identity
            if let key, blocks.last?.key == key {
                // The cells of one table row share a paragraph, a space apart.
                if let cell, cell != lastCell {
                    blocks[blocks.count - 1].text += AttributedString(" ")
                }
                blocks[blocks.count - 1].text += piece
            } else {
                let kind: Block.Kind = if inline.contains(.blockHTML) {
                    .html
                } else if components.contains(where: { Self.isCodeBlock($0.kind) }) {
                    .code
                } else {
                    .text
                }
                blocks.append(Block(key: key, style: Self.style(of: components), kind: kind, text: piece))
            }
            lastCell = cell
        }

        mutating func appendParagraph(_ text: String) {
            blocks.append(Block(key: nil, style: .paragraph, kind: .text, text: AttributedString(text)))
        }

        /// Joins blocks with bare `\n` separators. A code block becomes one
        /// paragraph per line, and an HTML block becomes whatever
        /// `RichTextHTML.decode` makes of it, so its text survives and its tags
        /// don't. Empty blocks are dropped: Markdown can't hold one, so there
        /// is nothing to keep.
        func finish() -> AttributedString {
            var result = AttributedString()
            for block in blocks {
                for line in lines(of: block) where !line.characters.isEmpty {
                    if !result.characters.isEmpty {
                        result += AttributedString("\n")
                    }
                    result += line
                }
            }
            return result
        }

        private func lines(of block: Block) -> [AttributedString] {
            switch block.kind {
            case .text:
                var line = block.text
                line.blockStyle = block.style
                return [line]
            case .code:
                return String(block.text.characters).split(separator: "\n").map {
                    var line = AttributedString(String($0))
                    line.blockStyle = block.style
                    return line
                }
            case .html:
                // A block of nothing but breaks (a lone `<br>`) is spacing,
                // which Markdown can't hold either.
                let decoded = RichTextHTML.decode(String(block.text.characters))
                return DocumentBlocks.split(decoded)
                    .map { AttributedString(decoded[$0.slice]) }
                    .filter { $0.characters.contains { !$0.isWhitespace } }
            }
        }

        /// List membership wins over a quote around it, since the flat model
        /// holds one role per block. A heading's level clamps to 1...3.
        static func style(of components: [PresentationIntent.IntentType]) -> BlockStyle {
            let itemCount = components.count { isListItem($0.kind) }
            if itemCount > 0 {
                // `components` runs innermost first.
                let innermostList = components.first { $0.kind == .orderedList || $0.kind == .unorderedList }
                return .listItem(innermostList?.kind == .orderedList ? .ordered : .unordered, depth: itemCount - 1)
            }
            for component in components {
                if case let .header(level) = component.kind {
                    return .heading(BlockStyle.clampedHeadingLevel(level))
                }
            }
            return components.contains { $0.kind == .blockQuote } ? .blockquote : .paragraph
        }

        private static func isListItem(_ kind: PresentationIntent.Kind) -> Bool {
            if case .listItem = kind {
                return true
            }
            return false
        }

        private static func isCodeBlock(_ kind: PresentationIntent.Kind) -> Bool {
            if case .codeBlock = kind {
                return true
            }
            return false
        }

        private static func isTableRow(_ kind: PresentationIntent.Kind) -> Bool {
            if case .tableRow = kind {
                return true
            }
            return false
        }

        private static func isTableCell(_ kind: PresentationIntent.Kind) -> Bool {
            if case .tableCell = kind {
                return true
            }
            return false
        }
    }
}
