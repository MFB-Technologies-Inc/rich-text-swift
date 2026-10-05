// EditorOptions.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import SwiftRichText

/// Every `RichTextEditor` and `.richTextToolbar` parameter, exposed so each can
/// be flipped at runtime.
struct EditorOptions: Hashable {
    var isEditable = true
    var pasteAsPlainText = false
    var placeholder = "Enter text here"
    var toolbar = ToolbarPreset.html
    var placement = Placement.bottom

    enum ToolbarPreset: String, CaseIterable, Identifiable {
        case none = "None"
        case `default` = "Default"
        case html = "HTML"
        case inlineOnly = "Inline only"
        case headingsFirst = "Headings first"

        var id: Self {
            self
        }

        /// `nil` means no toolbar modifier at all.
        var controls: [RichTextControl]? {
            switch self {
            case .none: nil
            case .default: .default
            case .html: .html
            case .inlineOnly: [.bold, .italic, .underline, .strikethrough, .textColor]
            case .headingsFirst: [.heading(.h1), .heading(.h2), .heading(.h3), .bold, .unorderedList]
            }
        }
    }

    enum Placement: String, CaseIterable, Identifiable {
        case top = "Top"
        case bottom = "Bottom"

        var id: Self {
            self
        }

        var value: RichTextToolbarPlacement {
            switch self {
            case .top: .top
            case .bottom: .bottom
            }
        }
    }
}
