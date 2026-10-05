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

    /// `default` plus the heading levels — the full v1 control set.
    /// Headings are an HTML-document concept, which is why they live here
    /// rather than in `default`.
    public static var html: [RichTextControl] {
        `default` + [.heading(.h1), .heading(.h2), .heading(.h3)]
    }
}
