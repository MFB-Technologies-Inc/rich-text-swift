// MarkdownTab.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import SwiftRichText
import SwiftUI

/// The live `RichTextMarkdown.encode` output of the editor's document, plus
/// the two round-trip checks worth watching while editing.
struct MarkdownTab: View {
    let document: AttributedString

    var body: some View {
        let markdown = RichTextMarkdown.encode(document)
        let decoded = RichTextMarkdown.decode(markdown)
        NavigationStack {
            List {
                Section {
                    CheckRow(
                        title: "decode(encode(doc)) == doc",
                        passes: decoded == document
                    )
                    CheckRow(
                        title: "encode(decode(markdown)) == markdown",
                        passes: RichTextMarkdown.encode(decoded) == markdown
                    )
                } header: {
                    Text("Round trip")
                } footer: {
                    Text(
                        "Underline, text color and empty paragraphs have no Markdown form, " +
                            "so a document using them fails the first check."
                    )
                }
                Section {
                    Text(markdown.isEmpty ? "(empty)" : markdown)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                } header: {
                    Text("Encoded Markdown")
                } footer: {
                    Text("\(markdown.utf8.count) bytes, \(document.characters.count) characters")
                }
            }
            .navigationTitle("Markdown")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Copy", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = markdown
                    }
                }
            }
        }
    }
}
