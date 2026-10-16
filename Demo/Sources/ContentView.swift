// ContentView.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import SwiftRichText
import SwiftUI

enum DemoTab: Hashable {
    case editor
    case html
    case markdown
    case load
}

/// Owns the one document every tab reads and writes, so an edit in the editor
/// shows up in the HTML tab and a load from the Load tab replaces what the
/// editor shows.
struct ContentView: View {
    @State private var document = RichTextHTML.decode(Sample.all[0].html)
    @State private var options = EditorOptions()
    @State private var selectedTab = DemoTab.editor

    var body: some View {
        TabView(selection: $selectedTab) {
            EditorTab(document: $document, options: $options)
                .tabItem { Label("Editor", systemImage: "character.cursor.ibeam") }
                .tag(DemoTab.editor)

            HTMLTab(document: document)
                .tabItem { Label("HTML", systemImage: "chevron.left.forwardslash.chevron.right") }
                .tag(DemoTab.html)

            MarkdownTab(document: document)
                .tabItem { Label("Markdown", systemImage: "text.document") }
                .tag(DemoTab.markdown)

            LoadTab(load: { html in
                document = RichTextHTML.decode(html)
                selectedTab = .editor
            }, loadMarkdown: { markdown in
                // Scaffold for #42: no Markdown codec yet, so import as plain
                // text verbatim. Markdown markers stay visible in the editor
                // until this becomes `RichTextMarkdown.decode(markdown)`.
                document = AttributedString(markdown)
                selectedTab = .editor
            })
            .tabItem { Label("Load", systemImage: "square.and.arrow.down") }
            .tag(DemoTab.load)
        }
    }
}
