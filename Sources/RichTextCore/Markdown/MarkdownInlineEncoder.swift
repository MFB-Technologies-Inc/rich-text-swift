// MarkdownInlineEncoder.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation

/// Writes one block's inline content: escaped text, `**`/`*`/`~~` marks, and
/// soft line breaks as backslash hard breaks.
///
/// Markdown marks are delimiter runs, not tags, so two rules from CommonMark
/// shape the output. A span that ends later is opened first, so `***a**b*`
/// nests without closing and reopening anything. And a delimiter must be
/// *flanking*: a closing `**` after punctuation must be followed by
/// whitespace or punctuation (so `"b"**c` is not bold), and two runs that
/// touch merge into one. Where either would happen, `separator` goes between.
enum MarkdownInlineEncoder {
    /// An inline mark Markdown can carry. Declaration order is the nesting
    /// order, outermost first, for marks that open and close together.
    enum Mark: Int, CaseIterable, Comparable {
        case bold, italic, strikethrough

        var delimiter: String {
            switch self {
            case .bold: "**"
            case .italic: "*"
            case .strikethrough: "~~"
            }
        }

        static func < (lhs: Mark, rhs: Mark) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    /// Splits two delimiter runs that would otherwise merge, or keeps a
    /// delimiter next to punctuation flanking, without adding text: the
    /// decoder drops inline HTML. Only ever written mid-line; at the start of
    /// a line it would open an HTML block.
    static let separator = "<!-- -->"

    private struct Segment {
        var characters: [Character]
        var marks: Set<Mark>
    }

    static func encode(_ text: AttributedSubstring, heading: Bool, continuation: String) -> String {
        let segments = segments(of: text, heading: heading)
        var out = ""
        var open: [Mark] = []
        var atLineStart = true
        for (index, segment) in segments.enumerated() {
            // Close from the outermost mark that ends here; any mark above it
            // that continues is reopened below.
            var closing: [Mark] = []
            if let outermostEnding = open.firstIndex(where: { !segment.marks.contains($0) }) {
                closing = open[outermostEnding...].reversed()
                open.removeSubrange(outermostEnding...)
            }
            let opening = segment.marks.subtracting(open).sorted {
                let lhsEnd = end(of: $0, from: index, in: segments)
                let rhsEnd = end(of: $1, from: index, in: segments)
                return lhsEnd != rhsEnd ? lhsEnd > rhsEnd : $0 < $1
            }
            open += opening
            let closeText = closing.map(\.delimiter).joined()
            let openText = opening.map(\.delimiter).joined()
            // Each mark's delimiter as its own run, when `***` would misparse.
            let openingRuns = innerMarkReopens(opening, from: index, in: segments)
                ? opening.map(\.delimiter)
                : sameCharacterRuns(openText)
            var lineStart = atLineStart && closeText.isEmpty && openText.isEmpty
            let body = body(segment.characters, heading: heading, continuation: continuation, atLineStart: &lineStart)
            atLineStart = lineStart

            out += delimiters(
                closing: closeText,
                opening: openingRuns,
                after: out.last,
                before: body
            ) + body
        }
        out += open.reversed().map(\.delimiter).joined()
        return out
    }

    /// Whether bold and italic open together here and the inner one reopens
    /// before the outer one closes, as in `***a* (b)*c***`. Written as one
    /// `***` run, the reopening `*` (punctuation on both sides, so it can
    /// open or close) may close the outer mark instead: CommonMark's rule of 3
    /// allows a 1-long closer to match what is left of a 3-long opener. As
    /// separate `**` and `*` runs it can't, since 2 + 1 is a multiple of 3.
    private static func innerMarkReopens(_ opening: [Mark], from index: Int, in segments: [Segment]) -> Bool {
        guard opening.contains(.bold), opening.contains(.italic) else {
            return false
        }
        let boldEnd = end(of: .bold, from: index, in: segments)
        let italicEnd = end(of: .italic, from: index, in: segments)
        guard boldEnd != italicEnd else {
            return false
        }
        let (inner, innerEnd, outerEnd) = boldEnd < italicEnd
            ? (Mark.bold, boldEnd, italicEnd)
            : (Mark.italic, italicEnd, boldEnd)
        return segments[innerEnd ..< outerEnd].contains { $0.marks.contains(inner) }
    }

    /// The block's characters grouped into runs of equal marks. Soft line
    /// breaks at the block's edges are dropped (a trailing backslash would
    /// read as text), a heading's become spaces, and every mark is pulled off
    /// whitespace at its edges.
    private static func segments(of text: AttributedSubstring, heading: Bool) -> [Segment] {
        var units = units(of: text, heading: heading)
        while units.first?.character == RichTextHTML.softLineBreak {
            units.removeFirst()
        }
        while units.last?.character == RichTextHTML.softLineBreak {
            units.removeLast()
        }
        for mark in Mark.allCases {
            pull(mark, offWhitespaceIn: &units)
        }
        var segments: [Segment] = []
        for unit in units {
            if segments.last?.marks == unit.marks {
                segments[segments.count - 1].characters.append(unit.character)
            } else {
                segments.append(Segment(characters: [unit.character], marks: unit.marks))
            }
        }
        return segments
    }

    private typealias Unit = (character: Character, marks: Set<Mark>)

    /// Each character with the marks Markdown can carry. A heading's soft
    /// line breaks become spaces, since a Markdown heading is one line.
    private static func units(of text: AttributedSubstring, heading: Bool) -> [Unit] {
        var units: [Unit] = []
        for run in text.runs {
            var marks = Set<Mark>()
            if run.bold == true {
                marks.insert(.bold)
            }
            if run.italic == true {
                marks.insert(.italic)
            }
            if run.strikethrough == true {
                marks.insert(.strikethrough)
            }
            for character in text[run.range].characters {
                let isBreak = character == RichTextHTML.softLineBreak
                units.append((heading && isBreak ? " " : character, marks))
            }
        }
        return units
    }

    /// Removes `mark` from whitespace at the edges of each of its spans.
    private static func pull(_ mark: Mark, offWhitespaceIn units: inout [Unit]) {
        var index = 0
        while index < units.count {
            guard units[index].marks.contains(mark) else {
                index += 1
                continue
            }
            var end = index
            while end < units.count, units[end].marks.contains(mark) {
                end += 1
            }
            var lower = index
            while lower < end, units[lower].character.isWhitespace {
                units[lower].marks.remove(mark)
                lower += 1
            }
            var upper = end
            while upper > lower, units[upper - 1].character.isWhitespace {
                units[upper - 1].marks.remove(mark)
                upper -= 1
            }
            index = end
        }
    }

    /// The index of the first segment after `index` without `mark`.
    private static func end(of mark: Mark, from index: Int, in segments: [Segment]) -> Int {
        var end = index
        while end < segments.count, segments[end].marks.contains(mark) {
            end += 1
        }
        return end
    }

    /// Escaped text, with each soft line break written as `\`, a newline and
    /// `continuation`. The text at the start of each line gets line-start
    /// escaping, since the line could otherwise begin a block.
    private static func body(
        _ characters: [Character],
        heading: Bool,
        continuation: String,
        atLineStart: inout Bool
    ) -> String {
        var out = ""
        let lines = characters.split(separator: RichTextHTML.softLineBreak, omittingEmptySubsequences: false)
        for (index, line) in lines.enumerated() {
            if index > 0 {
                out += "\\\n" + continuation
                atLineStart = true
            }
            guard !line.isEmpty else {
                continue
            }
            let text = String(line)
            if heading {
                out += MarkdownEscaping.escapeHeading(text)
            } else if atLineStart {
                out += MarkdownEscaping.escapeLineStart(text)
            } else {
                out += MarkdownEscaping.escapeInline(text)
            }
            atLineStart = false
        }
        return out
    }
}
