// UIKitEditorEngine+EditNormalization.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

#if canImport(UIKit)
    import RichTextCore
    import UIKit

    extension UIKitEditorEngine {
        /// `EngineCore.normalizedIngest` for a document UIKit just edited.
        /// Text the edit put in with no block role takes the role of the block
        /// where the edit started, as a paste does (GitHub issue #73). That is
        /// how typing over a selection that spans a heading and a list keeps
        /// the heading. Text before an edit doesn't move, so the first roleless
        /// character's offset is where the edit started in the document as it
        /// was before, too. The selection can't say: UIKit has already moved it
        /// past the inserted text.
        func normalizedEdit(_ edited: AttributedString) -> (text: AttributedString, selection: TextSelection)? {
            let startStyle = EngineCore.firstRolelessOffset(in: edited).flatMap {
                BlockScanner.blocks(of: semanticText, intersecting: .caret(at: $0)).first?.style
            }
            return EngineCore.normalizedIngest(
                edited,
                selection: selection,
                missingBlockStyle: startStyle ?? .paragraph
            )
        }
    }
#endif
