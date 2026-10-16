// LoadTab.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import SwiftUI

/// Loads a built-in sample or hand-written HTML into the editor through
/// `RichTextHTML.decode`, and Markdown through the Markdown load path
/// (plain-text import until `RichTextMarkdown.decode` lands in #42).
struct LoadTab: View {
    let load: (String) -> Void
    let loadMarkdown: (String) -> Void
    @State private var customHTML = ""
    @State private var customMarkdown = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Samples") {
                    ForEach(Sample.all) { sample in
                        Button {
                            load(sample.html)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(sample.name)
                                Text(sample.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions {
                            Button("Edit") { customHTML = sample.html }
                                .tint(.blue)
                        }
                    }
                }
                Section {
                    TextEditor(text: $customHTML)
                        .font(.system(.footnote, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .frame(minHeight: 160)
                    Button("Load into editor") {
                        load(customHTML)
                    }
                    .disabled(customHTML.isEmpty)
                } header: {
                    Text("Custom HTML")
                } footer: {
                    Text("Swipe a sample left and tap Edit to copy its HTML here.")
                }
                Section("Markdown samples") {
                    ForEach(MarkdownSample.all) { sample in
                        Button {
                            loadMarkdown(sample.markdown)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(sample.name)
                                Text(sample.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions {
                            Button("Edit") { customMarkdown = sample.markdown }
                                .tint(.blue)
                        }
                    }
                }
                Section {
                    TextEditor(text: $customMarkdown)
                        .font(.system(.footnote, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .frame(minHeight: 160)
                    Button("Load into editor") {
                        loadMarkdown(customMarkdown)
                    }
                    .disabled(customMarkdown.isEmpty)
                } header: {
                    Text("Custom Markdown")
                } footer: {
                    Text(
                        "Until #42 lands this imports as plain text, so markers stay visible. " +
                            "Swipe a Markdown sample left and tap Edit to copy it here."
                    )
                }
            }
            .navigationTitle("Load")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
