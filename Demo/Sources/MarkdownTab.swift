// MarkdownTab.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import SwiftRichText
import SwiftUI

/// The live `RichTextMarkdown.encode` output of the editor's document, plus
/// the two round-trip checks worth watching while editing.
///
/// Every tab shows the editor's one document, which may hold formatting
/// Markdown can't (the default sample has underline and color). Then
/// `decode(encode(doc)) == doc` can't hold by design, so that check reads
/// "Not applicable" with the reason rather than failing: a red mark here
/// always means a real codec bug.
struct MarkdownTab: View {
    let document: AttributedString

    var body: some View {
        let markdown = RichTextMarkdown.encode(document)
        let decoded = RichTextMarkdown.decode(markdown)
        let unsupported = Self.unsupportedFormatting(in: document)
        NavigationStack {
            List {
                Section {
                    if unsupported.isEmpty {
                        CheckRow(
                            title: "decode(encode(doc)) == doc",
                            passes: decoded == document
                        )
                    } else {
                        NotApplicableRow(title: "decode(encode(doc)) == doc")
                    }
                    CheckRow(
                        title: "encode(decode(markdown)) == markdown",
                        passes: RichTextMarkdown.encode(decoded) == markdown
                    )
                } header: {
                    Text("Round trip")
                } footer: {
                    if !unsupported.isEmpty {
                        Text(
                            "This document uses \(ListFormatter.localizedString(byJoining: unsupported)), " +
                                "which Markdown can't hold, so the first check doesn't apply. " +
                                "Remove that formatting, or load a Markdown sample, to see it pass."
                        )
                    }
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

    /// What `document` holds that `RichTextMarkdown` can't save, as phrases
    /// for the footer. Black counts as no color, as everywhere in the editor.
    static func unsupportedFormatting(in document: AttributedString) -> [String] {
        var found: [String] = []
        if document.runs.contains(where: { $0.underline == true }) {
            found.append("underline")
        }
        if document.runs.contains(where: { $0.textColor.map { $0 != .black } ?? false }) {
            found.append("text color")
        }
        let blocks = String(document.characters).split(separator: "\n", omittingEmptySubsequences: false)
        if !document.characters.isEmpty, blocks.contains(where: \.isEmpty) {
            found.append("empty paragraphs")
        }
        return found
    }
}

/// A check that can't hold for the current document by design, shown
/// neutrally so it doesn't read as a failure.
private struct NotApplicableRow: View {
    let title: String

    var body: some View {
        LabeledContent {
            Text("Not applicable")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } label: {
            Text(title)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}
