// RichTextControl+Presets.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

extension [RichTextControl] {
    /// The controls a consumer gets when they don't name any: inline
    /// formatting plus the two list kinds. Seven controls, which also happens
    /// to fit a phone's width without scrolling.
    public static var `default`: [RichTextControl] {
        [.bold, .italic, .underline, .strikethrough, .textColor, .unorderedList, .orderedList]
    }

    /// Every control the HTML format can represent: inline formatting and
    /// lists, with text color and the heading levels in one `.format` panel.
    /// Seven controls, so it fits a phone's width without scrolling even in a
    /// padded layout. Use it when you save documents with `RichTextHTML`.
    /// It only ever holds controls that survive an HTML round trip, so
    /// formatting added later that HTML can't hold stays out of it.
    public static var html: [RichTextControl] {
        [.bold, .italic, .underline, .strikethrough, .unorderedList, .orderedList, .format]
    }
}
