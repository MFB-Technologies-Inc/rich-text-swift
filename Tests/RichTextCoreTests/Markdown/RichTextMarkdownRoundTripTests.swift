// RichTextMarkdownRoundTripTests.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
@testable import RichTextCore
import Testing

struct RichTextMarkdownRoundTripTests {
    private func expectRoundTrip(_ document: AttributedString, sourceLocation: SourceLocation = #_sourceLocation) {
        let markdown = RichTextMarkdown.encode(document)
        let decoded = RichTextMarkdown.decode(markdown)
        #expect(
            decoded == document,
            """
            Markdown: \(markdown.debugDescription)
            expected: \(document.markdownTestDescription)
            decoded:  \(decoded.markdownTestDescription)
            """,
            sourceLocation: sourceLocation
        )
    }

    @Test func blockCases() {
        expectRoundTrip(Sem.block("Hello"))
        expectRoundTrip(Sem.doc(Sem.block("T", .heading(1)), Sem.block("body"), Sem.block("q", .blockquote)))
        expectRoundTrip(Sem.doc(Sem.block("a", .blockquote), Sem.block("b", .blockquote)))
        expectRoundTrip(Sem.doc(
            Sem.block("a", .listItem(.unordered, depth: 0)),
            Sem.block("b", .listItem(.ordered, depth: 1)),
            Sem.block("c", .listItem(.unordered, depth: 2)),
            Sem.block("d", .listItem(.unordered, depth: 0)),
            Sem.block("e", .listItem(.ordered, depth: 0))
        ))
        expectRoundTrip(Sem.doc(
            Sem.block("a", .listItem(.unordered, depth: 0)),
            Sem.block("c", .listItem(.ordered, depth: 2))
        ))
        expectRoundTrip(Sem.block("c", .listItem(.unordered, depth: 2)))
    }

    @Test func softBreakCases() {
        expectRoundTrip(Sem.block("a\u{2028}b"))
        expectRoundTrip(Sem.block("a\u{2028}b", .listItem(.ordered, depth: 0)))
        expectRoundTrip(Sem.block("a\u{2028}b", .listItem(.unordered, depth: 1)))
        expectRoundTrip(Sem.block("a\u{2028}b", .blockquote))
        expectRoundTrip(MD.block(.paragraph, MD.run("a\u{2028}b", .bold)))
    }

    @Test func inlineCases() {
        expectRoundTrip(MD.block(.paragraph, MD.run("ab", .bold), MD.run("c", .bold, .italic), MD.run("d", .italic)))
        expectRoundTrip(MD.block(.paragraph, MD.run("a"), MD.run("\"b\"", .bold, .strikethrough), MD.run("c")))
        expectRoundTrip(MD.block(.paragraph, MD.run("a", .strikethrough, .bold), MD.run("b")))
        expectRoundTrip(MD.block(.heading(2), MD.run("T", .italic), MD.run(" x")))
        // A strikethrough beside a `*` run, which Foundation's parser reads
        // inconsistently.
        expectRoundTrip(MD.block(.paragraph, MD.run("(a)", .bold), MD.run("b", .strikethrough)))
        expectRoundTrip(MD.block(.paragraph, MD.run("a", .strikethrough), MD.run("= q", .italic)))
        expectRoundTrip(MD.block(.paragraph, MD.run("x"), MD.run("\"b\"", .bold, .strikethrough), MD.run("y")))
        // A mid-word opener inside a mark still open.
        expectRoundTrip(MD.block(
            .paragraph,
            MD.run("p", .bold, .italic),
            MD.run(" x", .bold),
            MD.run("q", .bold, .italic)
        ))
        // Italic reopening inside bold, between punctuation (rule of 3).
        expectRoundTrip(MD.block(
            .paragraph,
            MD.run("+", .bold, .italic),
            MD.run(" ~", .bold),
            MD.run("+", .bold, .italic)
        ))
    }

    @Test func tenItemsKeepTheirChildren() {
        var blocks = (1 ... 12).map { Sem.block("i\($0)", .listItem(.ordered, depth: 0)) }
        blocks.insert(Sem.block("k", .listItem(.unordered, depth: 1)), at: 10)
        expectRoundTrip(blocks.dropFirst().reduce(blocks[0]) { $0 + AttributedString("\n") + $1 })
    }

    private static let literals = [
        "\\", "*", "_", "`", "~", "[", "]", "<", ">", "&", "|", "!", "#", "-", "+", "=", ".",
        "1.", "1)", "---", "***", "___", "~~~", "```", "a*b*c", "a_b_c", "**x**", "~~x~~", "[x](y)",
        "![x](y)", "<b>", "<!-- c -->", "&amp;", "&#42;", "a | b", "# x", "- x", "+ x", "* x", "> x",
        "1. x", "2024) x", "===", "x\\", "\\*", "https://x.com",
    ]

    @Test(arguments: literals)
    func literalTextStaysText(_ text: String) {
        expectRoundTrip(Sem.block(text))
        expectRoundTrip(Sem.block("x " + text))
        expectRoundTrip(Sem.block("x\u{2028}" + text))
        expectRoundTrip(Sem.block(text, .listItem(.unordered, depth: 0)))
        expectRoundTrip(Sem.block(text, .listItem(.ordered, depth: 1)))
        expectRoundTrip(Sem.block(text, .blockquote))
        expectRoundTrip(Sem.block("x " + text, .heading(2)))
        expectRoundTrip(MD.block(.paragraph, MD.run("x "), MD.run(text, .bold), MD.run(" y")))
        expectRoundTrip(MD.block(.paragraph, MD.run("x"), MD.run(text, .italic), MD.run("y")))
    }

    @Test func headingKeepsTrailingHashes() {
        expectRoundTrip(Sem.block("Title #", .heading(1)))
    }

    @Test func canonicalMarkdownIsIdempotent() {
        for markdown in [
            "# Title\n\nBody with **bold**, *italic* and ~~strike~~.",
            "- a\n  - b\n    1. c\n- d",
            "1. one\n2. two",
            "> quote\\\n> more",
            "***a**b*",
        ] {
            #expect(RichTextMarkdown.encode(RichTextMarkdown.decode(markdown)) == markdown)
        }
    }

    /// Seeded random documents in canonical form, to catch the interactions
    /// hand-picked cases miss: marks next to punctuation, breaks, nesting.
    @Test func generatedDocumentsRoundTrip() {
        var random = SplitMix64(seed: 42)
        for _ in 0 ..< 2000 {
            expectRoundTrip(Self.randomDocument(&random))
        }
    }

    private static let words = [
        "a", "Bc", "x1", "é", "\"q\"", "(p)", "*", "**", "_", "#", "1.", "2)", "-", "+", ">", "=",
        "~", "~~", "`", "[l]", "<t>", "&amp;", "a|b", "\\", "!", "a-b", "--", "***", "x.", "9",
        "😀", "→", "€", "©", "a\u{00A0}b", "(😀)",
    ]

    private static func randomDocument(_ random: inout SplitMix64) -> AttributedString {
        var document = AttributedString()
        var depth = -1
        for index in 0 ..< random.next(1 ... 6) {
            let style: BlockStyle
            switch random.next(0 ... 5) {
            case 0:
                style = .heading(random.next(1 ... 3))
                depth = -1
            case 1:
                style = .blockquote
                depth = -1
            case 2, 3:
                depth = min(depth + 2, random.next(0 ... 3))
                style = .listItem(random.next(0 ... 1) == 0 ? .ordered : .unordered, depth: depth)
            default:
                style = .paragraph
                depth = -1
            }
            if index > 0 {
                document += AttributedString("\n")
            }
            document += randomBlock(&random, style: style)
        }
        return document
    }

    private static func randomBlock(_ random: inout SplitMix64, style: BlockStyle) -> AttributedString {
        var isHeading = false
        if case .heading = style {
            isHeading = true
        }
        var block = AttributedString()
        var previousMarks: Set<MD.Mark>?
        for _ in 0 ..< random.next(1 ... 6) {
            var marks = Set<MD.Mark>()
            if random.next(0 ... 3) == 0 {
                marks.insert(.bold)
            }
            if random.next(0 ... 3) == 0 {
                marks.insert(.italic)
            }
            if random.next(0 ... 4) == 0 {
                marks.insert(.strikethrough)
            }
            if let previousMarks {
                // A gap carries only the marks on both sides, so no mark
                // starts or ends on whitespace. No gap at all puts a mark
                // boundary mid-word, next to whatever the words end with.
                switch random.next(0 ... 5) {
                case 0 where !isHeading:
                    block += MD.run("\u{2028}", marks: previousMarks.intersection(marks))
                case 1:
                    break
                default:
                    block += MD.run(" ", marks: previousMarks.intersection(marks))
                }
            }
            block += MD.run(words[random.next(0 ... words.count - 1)], marks: marks)
            previousMarks = marks
        }
        block.blockStyle = style
        return block
    }
}
