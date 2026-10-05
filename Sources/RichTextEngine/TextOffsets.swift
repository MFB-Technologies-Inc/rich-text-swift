// TextOffsets.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation

/// Converts between UTF-16 offsets (the `NSRange` currency the engine speaks —
/// see M3 decision D9) and `AttributedString.Index` values.
///
/// Foundation-only on purpose: this is the one piece of genuinely fiddly
/// bridging in the engine, so it lives where `swift test` can cover it on macOS
/// instead of inside the untested UIKit adapter.
enum TextOffsets {
    /// Total length of `text` in UTF-16 units.
    static func length(of text: AttributedString) -> Int {
        var total = 0
        for character in text.characters {
            total += String(character).utf16.count
        }
        return total
    }

    /// The index `offset` UTF-16 units from the start, clamped to
    /// `startIndex...endIndex`. An offset that lands *inside* a character
    /// resolves to the boundary after it (never an invalid split).
    static func index(at offset: Int, in text: AttributedString) -> AttributedString.Index {
        if offset <= 0 {
            return text.startIndex
        }
        var consumed = 0
        var index = text.startIndex
        while index < text.endIndex {
            if consumed >= offset {
                return index
            }
            consumed += String(text.characters[index]).utf16.count
            index = text.index(afterCharacter: index)
        }
        return text.endIndex
    }

    /// The UTF-16 offset of `index` from the start of `text`.
    static func offset(of index: AttributedString.Index, in text: AttributedString) -> Int {
        var consumed = 0
        var cursor = text.startIndex
        while cursor < index, cursor < text.endIndex {
            consumed += String(text.characters[cursor]).utf16.count
            cursor = text.index(afterCharacter: cursor)
        }
        return consumed
    }

    /// The index range a selection covers, clamped to `text`.
    static func range(_ selection: TextSelection, in text: AttributedString) -> Range<AttributedString.Index> {
        let lower = index(at: selection.lowerBound, in: text)
        let upper = index(at: selection.upperBound, in: text)
        return lower < upper ? lower ..< upper : lower ..< lower
    }
}
