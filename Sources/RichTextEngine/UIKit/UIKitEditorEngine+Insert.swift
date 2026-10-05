// UIKitEditorEngine+Insert.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

#if canImport(UIKit)
    import RichTextCore
    import UIKit

    extension UIKitEditorEngine {
        /// Replaces the selection with a semantic fragment, such as a decoded
        /// rich paste, and renders it in the theme. The splice
        /// rule is `EngineCore.insert`'s.
        ///
        /// Unlike `apply(_:)`, this is a text edit the user made in the view,
        /// so it reports itself through `textViewDidChange` the way UIKit's
        /// own paste does. That is what reaches the SwiftUI binding; nothing
        /// here knows about the model.
        public func insert(_ fragment: AttributedString) {
            let before = undoSnapshot()
            // `insert` is public, so the fragment may carry line endings or
            // explicit black that no decoder normalized. The caret is in
            // `semanticText`, not the fragment, so no selection maps.
            let result = EngineCore.insert(
                EngineCore.normalizedIngest(fragment, selection: .caret(at: 0))?.text ?? fragment,
                in: semanticText,
                selection: selection,
                typingAttributes: typingAttributes
            )
            guard result.text != before.text else {
                return
            }
            registerUndo(restoring: before)
            semanticText = result.text
            typingAttributes = result.typingAttributes
            render(restoring: result.selection)
            lastAttributesSelection = selection
            pushTypingAttributes()
            textView.delegate?.textViewDidChange?(textView)
        }
    }
#endif
