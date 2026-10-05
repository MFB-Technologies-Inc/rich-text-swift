// TextViewStorageWriter.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

#if canImport(UIKit)
    import RichTextCore
    import UIKit

    /// Writes a rendered `NSAttributedString` into a live `UITextView` and
    /// restores the caret.
    ///
    /// Split out of `UIKitEditorEngine.render(restoring:)` because it is the
    /// one part of a render that talks to UIKit's text-input machinery rather
    /// than to the engine's own state: it needs the text view and the
    /// selection to restore, and nothing else.
    @MainActor
    enum TextViewStorageWriter {
        /// Returns whether the characters changed (as opposed to attributes
        /// only), so a caller that is not recording its own undo entry knows
        /// the text view's existing undo history no longer describes the
        /// document.
        ///
        /// `selectionIndexesRendered` says `selection` was already mapped onto
        /// `rendered`, so a character replacement keeps it as a range instead
        /// of collapsing it to a caret.
        @discardableResult
        static func write(
            _ rendered: NSAttributedString,
            to textView: UITextView,
            restoring selection: TextSelection,
            selectionIndexesRendered: Bool = false
        ) -> Bool {
            let storage = textView.textStorage
            let fullRange = NSRange(location: 0, length: rendered.length)
            let replacesCharacters = !(storage.length == rendered.length && storage.string == rendered.string)

            // Mutating `textStorage` directly bypasses `UITextView`'s text-input
            // machinery, which keeps its own snapshot of the document. Without
            // these notifications `_UIKeyboardStateManager` goes on believing the
            // old length, and the next selection change makes its tokenizer read
            // past the end — an uncatchable `NSRangeException` thrown from inside
            // UIKit (observed switching between example-app samples: it asked for
            // {9, 109} against a 109-length string). Only the character-replacing
            // path needs this; an attributes-only pass leaves the text identical.
            let inputDelegate = textView.inputDelegate
            if replacesCharacters {
                inputDelegate?.textWillChange(textView)
            }
            // Swift `String` equality is canonical (Unicode) equivalence, not
            // UTF-16 code-unit equality — e.g. "caf\u{00E9}" == "cafe\u{0301}" is
            // true even though their NSString lengths differ (4 vs 5). `fullRange`
            // above is sized from `rendered.length`, so relying on the string
            // comparison alone could hand `setAttributes(_:range:)` a range past
            // the end of `storage`, either crashing with an out-of-range
            // `NSRangeException` or silently leaving a trailing suffix unstyled.
            // The length check is therefore not redundant with the string check.
            if replacesCharacters {
                storage.setAttributedString(rendered)
            } else {
                rendered.enumerateAttributes(in: fullRange) { attributes, range, _ in
                    storage.setAttributes(attributes, range: range)
                }
            }
            // Committed *before* the selection is touched: `clamp` reads
            // `textView.textStorage.length`, and inside an open editing
            // transaction that length is not yet the one the text view will
            // report, so clamping against it can produce a range past the end.
            storage.endEditing()
            if replacesCharacters {
                inputDelegate?.textDidChange(textView)
            }

            // Restoring an old *range* into a document that just changed
            // wholesale is meaningless — and it is what fed UIKit the bad range —
            // so a replacement collapses to a caret unless the caller mapped it.
            let restored = replacesCharacters && !selectionIndexesRendered
                ? NSRange(location: selection.location, length: 0)
                : NSRange(location: selection.location, length: selection.length)
            inputDelegate?.selectionWillChange(textView)
            textView.selectedRange = clamp(restored, in: textView)
            inputDelegate?.selectionDidChange(textView)
            return replacesCharacters
        }

        private static func clamp(_ range: NSRange, in textView: UITextView) -> NSRange {
            let length = textView.textStorage.length
            let location = min(max(0, range.location), length)
            return NSRange(location: location, length: min(range.length, length - location))
        }
    }
#endif
