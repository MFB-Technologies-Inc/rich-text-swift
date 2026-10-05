// HTMLTab.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import SwiftRichText
import SwiftUI

/// The live `RichTextHTML.encode` output of the editor's document, plus the two
/// round-trip checks worth watching while editing.
struct HTMLTab: View {
    let document: AttributedString

    var body: some View {
        let html = RichTextHTML.encode(document)
        let decoded = RichTextHTML.decode(html)
        NavigationStack {
            List {
                Section("Round trip") {
                    CheckRow(
                        title: "decode(encode(doc)) == doc",
                        passes: decoded == document
                    )
                    CheckRow(
                        title: "encode(decode(html)) == html",
                        passes: RichTextHTML.encode(decoded) == html
                    )
                }
                Section {
                    Text(html.isEmpty ? "(empty)" : html)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                } header: {
                    Text("Encoded HTML")
                } footer: {
                    Text("\(html.utf8.count) bytes, \(document.characters.count) characters")
                }
            }
            .navigationTitle("HTML")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Copy", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = html
                    }
                }
            }
        }
    }
}

private struct CheckRow: View {
    let title: String
    let passes: Bool

    var body: some View {
        LabeledContent {
            Image(systemName: passes ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .foregroundStyle(passes ? .green : .red)
                .accessibilityLabel(passes ? "Passes" : "Fails")
        } label: {
            Text(title)
                .font(.system(.footnote, design: .monospaced))
        }
    }
}
