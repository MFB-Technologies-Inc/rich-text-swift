// EditorTab.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import SwiftRichText
import SwiftUI

struct EditorTab: View {
    @Binding var document: AttributedString
    @Binding var options: EditorOptions
    @State private var isShowingOptions = false

    var body: some View {
        NavigationStack {
            editor
                .padding(.horizontal)
                .navigationTitle("Editor")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Clear", role: .destructive) {
                            document = AttributedString()
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Options", systemImage: "slider.horizontal.3") {
                            isShowingOptions = true
                        }
                    }
                }
                .sheet(isPresented: $isShowingOptions) {
                    OptionsSheet(options: $options)
                        .presentationDetents([.medium, .large])
                }
        }
    }

    /// Rebuilt from scratch whenever an option changes. The toolbar modifier
    /// adopts its model once per view identity, so swapping presets on a live
    /// hierarchy would test a configuration no real app ever ships.
    @ViewBuilder
    private var editor: some View {
        let base = RichTextEditor(
            text: $document,
            isEditable: options.isEditable,
            placeholder: options.placeholder.isEmpty ? nil : options.placeholder,
            pasteAsPlainText: options.pasteAsPlainText
        )
        Group {
            if let controls = options.toolbar.controls {
                base.richTextToolbar(controls, placement: options.placement.value)
            } else {
                base
            }
        }
        .id(options)
    }
}

private struct OptionsSheet: View {
    @Binding var options: EditorOptions
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Editor") {
                    Toggle("Editable", isOn: $options.isEditable)
                    Toggle("Paste as plain text", isOn: $options.pasteAsPlainText)
                    TextField("Placeholder (empty for none)", text: $options.placeholder)
                }
                Section("Toolbar") {
                    Picker("Controls", selection: $options.toolbar) {
                        ForEach(EditorOptions.ToolbarPreset.allCases) { preset in
                            Text(preset.rawValue).tag(preset)
                        }
                    }
                    Picker("Placement", selection: $options.placement) {
                        ForEach(EditorOptions.Placement.allCases) { placement in
                            Text(placement.rawValue).tag(placement)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(options.toolbar.controls == nil)
                }
                Section {
                    Button("Reset to defaults") {
                        options = EditorOptions()
                    }
                }
            }
            .navigationTitle("Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
