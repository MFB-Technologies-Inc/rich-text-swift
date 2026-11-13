// MarkdownSample.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

/// Markdown documents that each exercise one area of Markdown mode. The Load
/// tab feeds them to `RichTextMarkdown.decode`.
struct MarkdownSample: Identifiable {
    let name: String
    let summary: String
    let markdown: String

    var id: String {
        name
    }

    static let all: [MarkdownSample] = [
        MarkdownSample(
            name: "Everything (Markdown)",
            summary: "Headings, inline styles, lists and a quote",
            markdown: """
            # SwiftRichText

            Body text with **bold**, *italic*, and ~~strikethrough~~.

            ## Lists

            - first
            - **second**

            1. one
            2. two
            3. three

            > A quoted paragraph.

            ### Small heading

            The end.
            """
        ),
        MarkdownSample(
            name: "Headings (Markdown)",
            summary: "H1–H3 today; H4–H6 arrive with #44",
            markdown: """
            # Heading 1

            paragraph

            ## Heading 2

            paragraph

            ### Heading 3

            paragraph
            """
        ),
        MarkdownSample(
            name: "Nested lists (Markdown)",
            summary: "Unordered and ordered lists, nested and mixed",
            markdown: """
            - top level
              - nested bullet
                - third level
            - back to top

            1. step one
               1. sub-step a
               2. sub-step b
            2. step two

            - bullet
              1. numbered inside a bullet
            """
        ),
        MarkdownSample(
            name: "Escaping (Markdown)",
            summary: "Literal Markdown-significant characters in prose",
            markdown: """
            # Not a heading in prose: \\# example

            A literal \\*asterisk\\*, a \\# hash, and 1\\. not a list.

            > Not only a quote marker: \\> in body text.
            """
        ),
        MarkdownSample(
            name: "Future formatting (Markdown)",
            summary: "Inline code, links, code blocks, tasks — #45 to #49",
            markdown: """
            Inline `code`, a [link](https://example.com), and a task list:

            - [ ] pending
            - [x] done

            ```swift
            let greeting = "hello"
            ```
            """
        ),
    ]
}
