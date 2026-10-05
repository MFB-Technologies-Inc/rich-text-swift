// EngineCore+Inline.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
import RichTextCore

extension EngineCore {
    /// The two kinds of inline edit: toggle a boolean flag, or set a color.
    enum InlineEdit {
        case flag(InlineFlag)
        case color(RichTextColor?)
    }

    /// Applies an inline edit to the selected characters, or — for a caret —
    /// to the typing attributes, so the next typed characters pick it up.
    static func applyInline(
        _ edit: InlineEdit,
        to text: AttributedString,
        selection: TextSelection,
        typingAttributes: TypingAttributes
    ) -> EditResult {
        var typing = typingAttributes

        guard !selection.isCollapsed else {
            switch edit {
            case let .flag(flag):
                typing[flag].toggle()
            case let .color(color):
                // Black is the absence of a text color everywhere in the
                // system (see `RichTextColor.black`); normalize here so the
                // model never stores an explicit black run in the first
                // place. Picking black in the `ColorPicker` — which cannot
                // express "no color" directly — is how the user removes one.
                typing.textColor = color == .black ? nil : color
            }
            return EditResult(text: text, selection: selection, typingAttributes: typing)
        }

        var result = text
        // Apply per block, clipped to the selection, so the `\n` separators are
        // left unattributed. A bold separator would round-trip differently:
        // `decode(encode(x))` re-joins blocks with a bare newline, so the model
        // would no longer equal itself after a serialization round trip.
        // (Mutation never changes lengths, so the offsets stay valid.)
        let segments = BlockScanner.blocks(of: text, intersecting: selection).compactMap { block -> TextSelection? in
            let lower = max(block.location, selection.lowerBound)
            let upper = min(block.location + block.length, selection.upperBound)
            return lower < upper ? TextSelection(location: lower, length: upper - lower) : nil
        }
        switch edit {
        case let .flag(flag):
            let current = formatState(of: text, selection: selection, typingAttributes: typingAttributes)[flag]
            // Off and mixed both turn the whole selection on; only a fully-on
            // selection turns off. Off is written as *removal* so the model
            // stays equal to a freshly decoded one.
            for segment in segments {
                setFlag(flag, current == .on ? nil : true, in: &result, range: TextOffsets.range(segment, in: result))
            }
            typing[flag] = current != .on
        case let .color(color):
            // Same normalization as the collapsed-selection branch above:
            // black never gets stored, it clears whatever color was there.
            let normalized = color == .black ? nil : color
            for segment in segments {
                result[TextOffsets.range(segment, in: result)].textColor = normalized
            }
            typing.textColor = normalized
        }
        // A pending block style only applies to an empty block; formatting real
        // characters means it is stale (M3 decision D13).
        typing.blockStyle = nil
        return EditResult(text: result, selection: selection, typingAttributes: typing)
    }
}
