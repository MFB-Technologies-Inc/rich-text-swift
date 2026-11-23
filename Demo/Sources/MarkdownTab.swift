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
/// Markdown can't (the default sample has underline and color). Losing that
/// on save is expected, so the first check compares against the document
/// without it, and the footer says what was left out. A red mark means a
/// real codec bug.
struct MarkdownTab: View {
    let document: AttributedString

    var body: some View {
        let markdown = RichTextMarkdown.encode(document)
        let decoded = RichTextMarkdown.decode(markdown)
        let unsupported = Self.unsupportedFormatting(in: document)
        NavigationStack {
            List {
                Section {
                    CheckRow(
                        title: "decode(encode(doc)) == doc",
                        passes: decoded == Self.markdownForm(of: document)
                    )
                    CheckRow(
                        title: "encode(decode(markdown)) == markdown",
                        passes: RichTextMarkdown.encode(decoded) == markdown
                    )
                } header: {
                    Text("Round trip")
                } footer: {
                    Text(Self.roundTripNote(unsupported: unsupported))
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

    /// Why the first check may fail, naming what this document holds that
    /// Markdown can't, if anything.
    static func roundTripNote(unsupported: [String]) -> String {
        guard !unsupported.isEmpty else {
            return "Underline, text color and empty paragraphs have no Markdown form, " +
                "so the first check leaves them out."
        }
        let list = ListFormatter.localizedString(byJoining: unsupported)
        return "Matches apart from this document's \(list), which Markdown can't hold. " +
            "They are dropped on save, as expected."
    }

    /// `document` as Markdown can hold it: without underline or text color,
    /// and without empty paragraphs. What `decode(encode(document))` should
    /// equal.
    static func markdownForm(of document: AttributedString) -> AttributedString {
        var stripped = document
        for run in document.runs {
            stripped[run.range].underline = nil
            stripped[run.range].textColor = nil
        }
        let blocks = stripped.characters.split(separator: "\n", omittingEmptySubsequences: false)
        guard blocks.contains(where: \.isEmpty) else {
            return stripped
        }
        // Rebuilt from the non-empty blocks with plain separators, the way
        // the decoder joins blocks.
        var result = AttributedString()
        var start = stripped.startIndex
        for block in blocks {
            let end = stripped.index(start, offsetByCharacters: block.count)
            if !block.isEmpty {
                if !result.characters.isEmpty {
                    result += AttributedString("\n")
                }
                result += stripped[start ..< end]
            }
            start = end < stripped.endIndex ? stripped.index(afterCharacter: end) : end
        }
        return result
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
