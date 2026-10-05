// EngineCore+Newline.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
import RichTextCore

extension EngineCore {
    /// The result of pressing Return. Pure, so the policy is
    /// covered by `swift test` on macOS and the platform adapter only has to
    /// intercept the keystroke.
    ///
    /// | Caret | Result |
    /// |---|---|
    /// | End of a list item | New item, same kind and depth |
    /// | In an **empty** list item | Leave the list: role cleared, no newline inserted |
    /// | End of a heading | New paragraph |
    /// | Split mid-heading | Two headings — the user styled that text deliberately |
    /// | Split mid-list-item | Two items, same kind and depth |
    /// | End of a blockquote | New paragraph (the only way out — no toolbar control) |
    /// | Split mid-blockquote | Two blockquotes, same as a heading |
    /// | Paragraph | Paragraph |
    static func insertNewline(
        in text: AttributedString,
        selection: TextSelection,
        typingAttributes: TypingAttributes
    ) -> EditResult {
        let caretBlock = BlockScanner.blocks(of: text, intersecting: selection).first
            ?? DocumentBlock(location: 0, length: 0, style: .paragraph)
        // An empty block's role lives in the pending typing attribute, since
        // Foundation cannot attribute zero-length content.
        let currentStyle = (caretBlock.isEmpty ? typingAttributes.blockStyle : nil) ?? caretBlock.style

        // Return on an empty list item leaves the list rather than adding an
        // empty one — the standard way out of a list.
        if caretBlock.isEmpty, case .listItem = currentStyle {
            var typing = typingAttributes
            typing.blockStyle = nil
            return EditResult(text: text, selection: selection, typingAttributes: typing)
        }

        // A bare newline: a separator carrying inline attributes would break
        // decode(encode(x)) == x.
        var result = text
        let insertionRange = TextOffsets.range(selection, in: result)
        // The requested offset may fall inside a character; resolve the caret
        // from where the splice actually lands, not the raw requested offset,
        // so a mid-surrogate-pair selection still returns a caret after the
        // inserted newline (Bug 2).
        let insertionOffset = TextOffsets.offset(of: insertionRange.lowerBound, in: result)
        result.replaceSubrange(insertionRange, with: AttributedString("\n"))
        let newSelection = TextSelection.caret(at: insertionOffset + 1)

        // Mid-block-split is decided from the post-edit document: the block
        // following the caret is what will carry `newStyle`, so the split is
        // "mid-block" exactly when that block is non-empty (Bug 1) — deciding
        // from pre-edit geometry gets it wrong once the selection spans a
        // block boundary.
        let newBlock = BlockScanner.blocks(of: result, intersecting: newSelection).first
        let splitsMidBlock = newBlock.map { !$0.isEmpty } ?? false

        // Which pre-edit block does the surviving content actually come from?
        // `currentStyle` is the caret block's role, which is correct only when
        // some of the caret block survives the edit:
        //   - Selection starts after the caret block's start: its head (the
        //     characters before the selection) survives and merges with
        //     whatever the tail contributes, so one shared role is right —
        //     the caret block's, exactly as before this fix.
        //   - Selection starts at the caret block's start but ends beyond its
        //     end: none of the caret block survives — it is annihilated
        //     wholesale — so stamping its role onto the surviving tail would
        //     silently retype content the user never selected. The role must
        //     instead come from whichever pre-edit block the selection's
        //     upper bound actually lands in, since that block is where the
        //     survivor came from.
        //   - Otherwise the selection is a single, block-start-anchored range
        //     entirely inside the caret block, so its own role still applies.
        let roleSource: BlockStyle
        if selection.lowerBound > caretBlock.location {
            roleSource = currentStyle
        } else if selection.upperBound > caretBlock.location + caretBlock.length {
            let tailBlock = BlockScanner.blocks(
                of: text,
                intersecting: TextSelection.caret(at: selection.upperBound)
            ).first
            roleSource = tailBlock?.style ?? currentStyle
        } else {
            roleSource = currentStyle
        }

        let newStyle: BlockStyle = switch roleSource {
        case let .listItem(kind, depth):
            .listItem(kind, depth: depth)
        case .heading, .blockquote:
            // Same rule for both, for the same two reasons:
            //   - Splitting mid-block keeps the role: the user deliberately
            //     made that text a heading / a quote, and handing the tail
            //     back as a paragraph silently unstyles content they never
            //     touched.
            //   - Return at the END of one exits to a paragraph, which is
            //     the only way out of a blockquote in v1 — there is no
            //     toolbar control for it (import/export fidelity only), so a
            //     quote that continued itself on Return would be a trap for
            //     anyone who opened an imported document.
            splitsMidBlock ? roleSource : .paragraph
        case .paragraph:
            .paragraph
        }

        var typing = typingAttributes
        if splitsMidBlock, let newBlock {
            let range = TextOffsets.range(
                TextSelection(location: newBlock.location, length: newBlock.length),
                in: result
            )
            result[range].blockStyle = newStyle
            typing.blockStyle = nil
        } else {
            // Nothing to carry the marker yet — hold it until characters exist.
            typing.blockStyle = newStyle
        }
        return EditResult(text: result, selection: newSelection, typingAttributes: typing)
    }
}
