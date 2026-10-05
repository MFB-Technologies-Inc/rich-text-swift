// LoadTab.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import SwiftUI

/// Loads a built-in sample or hand-written HTML into the editor through
/// `RichTextHTML.decode`.
struct LoadTab: View {
    let load: (String) -> Void
    @State private var customHTML = ""

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
            }
            .navigationTitle("Load")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
