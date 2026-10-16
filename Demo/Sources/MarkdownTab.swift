// MarkdownTab.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import SwiftRichText
import SwiftUI

/// Scaffold for the live `RichTextMarkdown` output of the editor's document.
///
/// The Markdown codec does not exist yet (see #42), so this tab deliberately
/// does not fake an encoding. It mirrors `HTMLTab`'s shape — round-trip checks
/// plus the encoded text — so that when `RichTextMarkdown.encode`/`decode`
/// land, this view only has to swap its placeholder rows for the real checks:
///
///     let markdown = RichTextMarkdown.encode(document)
///     let decoded = RichTextMarkdown.decode(markdown)
///     // decode(encode(doc)) == doc
///     // encode(decode(markdown)) == markdown
///
/// Until then it shows the document's plain text and marks the codec as
/// not yet implemented, so the Demo compiles and the missing piece is visible
/// rather than silently absent.
struct MarkdownTab: View {
    let document: AttributedString

    var body: some View {
        NavigationStack {
            List {
                Section {
                    PendingRow(title: "decode(encode(doc)) == doc")
                    PendingRow(title: "encode(decode(markdown)) == markdown")
                } header: {
                    Text("Round trip")
                } footer: {
                    Text("Pending RichTextMarkdown (#42). Checks will mirror the HTML tab once the codec lands.")
                }

                Section {
                    Text(plainText.isEmpty ? "(empty)" : plainText)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                } header: {
                    Text("Document text")
                } footer: {
                    Text("Markdown encoding will replace this preview. \(document.characters.count) characters.")
                }
            }
            .navigationTitle("Markdown")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var plainText: String {
        String(document.characters)
    }
}

private struct PendingRow: View {
    let title: String

    var body: some View {
        LabeledContent {
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
                .accessibilityLabel("Not yet implemented")
        } label: {
            Text(title)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}
