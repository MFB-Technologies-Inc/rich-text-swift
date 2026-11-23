// UIKitEditorEngine+Formatting.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

#if canImport(UIKit)
    import RichTextCore
    import UIKit

    extension UIKitEditorEngine {
        /// Brings the document, typing attributes and undo history in line
        /// with a changed `allowedFormatting`.
        func applyAllowedFormatting(replacing oldValue: RichTextFormatting) {
            // The `text` setter strips the document against the new profile
            // and handles a real change like any replacement: re-render, fresh
            // typing attributes, undo history cleared.
            text = semanticText
            // Undo restores snapshots without stripping them, so history from
            // before a narrower profile could bring back what it now
            // disallows, even when the document itself had none left to strip
            // and the setter above kept the history.
            if !allowedFormatting.isSuperset(of: oldValue) {
                caretCommandStates = []
                clearUndoHistoryWhenSafe()
            }
            // A caret's typing attributes may hold formatting the profile now
            // excludes even when the document has none of it.
            let stripped = EngineCore.strippingDisallowed(typingAttributes, allowing: allowedFormatting)
            if stripped != typingAttributes {
                typingAttributes = stripped
                pushTypingAttributes()
            }
        }
    }
#endif
