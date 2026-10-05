// TextSelection.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation

/// A selection in the flat document, expressed in **UTF-16 offsets** so it maps
/// 1:1 onto `NSRange` (`UITextView.selectedRange` / `NSTextView`). The engine
/// never stores `AttributedString.Index` values — mutation invalidates them.
public struct TextSelection: Hashable, Sendable {
    /// UTF-16 offset of the selection start.
    public var location: Int
    /// Length in UTF-16 units. `0` == a caret.
    public var length: Int

    public init(location: Int, length: Int) {
        self.location = max(0, location)
        self.length = max(0, length)
    }

    /// A zero-length selection (caret) at `offset`.
    public static func caret(at offset: Int) -> TextSelection {
        TextSelection(location: offset, length: 0)
    }

    public var isCollapsed: Bool {
        length == 0
    }

    public var lowerBound: Int {
        location
    }

    public var upperBound: Int {
        location + length
    }
}
