// EngineCore+Formatting.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
import RichTextCore

extension EngineCore {
    /// `text` with everything `allowed` excludes removed: disallowed inline
    /// marks and color are cleared, and a block with a disallowed role becomes
    /// a paragraph. The characters never change.
    static func strippingDisallowed(
        _ text: AttributedString,
        allowing allowed: RichTextFormatting
    ) -> AttributedString {
        guard !allowed.isSuperset(of: .all) else {
            return text
        }
        var result = text
        for run in text.runs {
            let range = run.range
            if run.bold != nil, !allowed.contains(.bold) {
                result[range].bold = nil
            }
            if run.italic != nil, !allowed.contains(.italic) {
                result[range].italic = nil
            }
            if run.underline != nil, !allowed.contains(.underline) {
                result[range].underline = nil
            }
            if run.strikethrough != nil, !allowed.contains(.strikethrough) {
                result[range].strikethrough = nil
            }
            if run.textColor != nil, !allowed.contains(.textColor) {
                result[range].textColor = nil
            }
            if let style = run.blockStyle, !allowed.allows(style) {
                result[range].blockStyle = .paragraph
            }
        }
        return result
    }

    /// `typingAttributes` without anything `allowed` excludes, so text typed
    /// next can't carry it either.
    static func strippingDisallowed(
        _ typingAttributes: TypingAttributes,
        allowing allowed: RichTextFormatting
    ) -> TypingAttributes {
        var result = typingAttributes
        for (flag, option) in [
            (InlineFlag.bold, RichTextFormatting.bold), (.italic, .italic),
            (.underline, .underline), (.strikethrough, .strikethrough),
        ] where !allowed.contains(option) {
            result[flag] = false
        }
        if !allowed.contains(.textColor) {
            result.textColor = nil
        }
        if let style = result.blockStyle, !allowed.allows(style) {
            result.blockStyle = .paragraph
        }
        return result
    }
}
