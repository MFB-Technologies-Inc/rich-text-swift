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

    /// Every control the HTML format can represent: `default` plus the
    /// heading levels. Use it when you save documents with `RichTextHTML`.
    /// It only ever holds controls that survive an HTML round trip, so
    /// formatting added later that HTML can't hold stays out of it.
    public static var html: [RichTextControl] {
        `default` + [.heading(.h1), .heading(.h2), .heading(.h3)]
    }

    /// Every control Markdown can represent: `html` without underline and
    /// text color, which have no Markdown form. Use it when you save
    /// documents as Markdown. Like `html`, it only ever holds controls that
    /// survive a round trip, so a user can't make formatting that is lost on
    /// save.
    ///
    /// This only limits the bar. Underline or color that arrives some other
    /// way, such as a rich paste, still shows in the editor and is dropped
    /// on save.
    public static var markdown: [RichTextControl] {
        [.bold, .italic, .strikethrough, .unorderedList, .orderedList, .heading(.h1), .heading(.h2), .heading(.h3)]
    }
}
