// SemanticNSBridge.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
import RichTextCore

/// Bridges the semantic `AttributedString` model to/from `NSAttributedString`,
/// carrying ONLY the core semantic attributes (block style + inline flags +
/// text color) — never rendering attributes (fonts, paragraph styles, colors
/// as `UIColor`/`NSColor`). Those are the platform adapter's job.
///
/// This is pure Foundation: `NSAttributedString` itself needs no UIKit/AppKit,
/// only the values *drawn from* it (fonts, etc.) do. Keeping the bridge here
/// — rather than inside the UIKit adapter — makes it unit-testable with
/// `swift test`, which is exactly how fix wave A closes the adapter's
/// round-trip defect: the adapter previously stamped block-separator `\n`
/// characters with the *following* block's `blockStyle`, so a document read
/// back from `NSAttributedString` was never equal to the one written to it.
/// That is a correctness bug the adapter cannot be trusted to get right by
/// hand — it belongs in tested code instead.
///
/// Module-internal: only the RichTextEngine adapters need this.
enum SemanticNSBridge {
    /// `NSAttributedString.Key` constants built from `RichTextAttributes`'
    /// key names, so the adapter and this bridge cannot disagree about them.
    static let blockStyleKey = NSAttributedString.Key(RichTextAttributes.BlockStyleKey.name)
    static let boldKey = NSAttributedString.Key(RichTextAttributes.BoldKey.name)
    static let italicKey = NSAttributedString.Key(RichTextAttributes.ItalicKey.name)
    static let underlineKey = NSAttributedString.Key(RichTextAttributes.UnderlineKey.name)
    static let strikethroughKey = NSAttributedString.Key(RichTextAttributes.StrikethroughKey.name)
    static let textColorKey = NSAttributedString.Key(RichTextAttributes.TextColorKey.name)

    /// The semantic attribute dictionary for one run: block style (if any),
    /// whichever inline flags are `true`, and the text color (if any). Values
    /// are the Swift values themselves (`BlockStyle`, `Bool`, `RichTextColor`)
    /// boxed as `Any` — sound because this dictionary never leaves the process.
    static func semanticAttributes(of slice: AttributedSubstring) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [:]
        if let style = slice.blockStyle {
            attributes[blockStyleKey] = style
        }
        if slice.bold == true {
            attributes[boldKey] = true
        }
        if slice.italic == true {
            attributes[italicKey] = true
        }
        if slice.underline == true {
            attributes[underlineKey] = true
        }
        if slice.strikethrough == true {
            attributes[strikethroughKey] = true
        }
        if let color = slice.textColor {
            attributes[textColorKey] = color
        }
        return attributes
    }

    /// The semantic attribute dictionary for text about to be typed: the given
    /// block style (if any), whichever inline flags in `typingAttributes` are
    /// `true`, and its text color (if any). Single owner for this mapping so
    /// the adapter doesn't hand-build it (and risk disagreeing with the rest
    /// of this bridge about which flags exist or when a block style is
    /// emitted).
    static func semanticAttributes(
        block: BlockStyle?,
        typingAttributes: TypingAttributes
    ) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [:]
        if let block {
            attributes[blockStyleKey] = block
        }
        if typingAttributes.bold {
            attributes[boldKey] = true
        }
        if typingAttributes.italic {
            attributes[italicKey] = true
        }
        if typingAttributes.underline {
            attributes[underlineKey] = true
        }
        if typingAttributes.strikethrough {
            attributes[strikethroughKey] = true
        }
        if let color = typingAttributes.textColor {
            attributes[textColorKey] = color
        }
        return attributes
    }

    /// The inverse of `semanticAttributes(block:typingAttributes:)`: rebuilds
    /// a `TypingAttributes` from a semantic attribute dictionary (e.g. one
    /// read straight off `UITextView.typingAttributes`). Single owner for
    /// this direction of the mapping too, so an adapter doesn't hand-roll it
    /// and risk enumerating the four inline flags plus color against their
    /// keys differently than the rest of this bridge does. Reads each known
    /// key with a conditional cast; an unknown key, or a known key with an
    /// unexpected value type, is silently ignored — never crashes, never
    /// guesses — matching `attributedString(from:)`'s tolerance.
    static func typingAttributes(from semantic: [NSAttributedString.Key: Any]) -> TypingAttributes {
        var typingAttributes = TypingAttributes()
        typingAttributes.blockStyle = semantic[blockStyleKey] as? BlockStyle
        typingAttributes.bold = (semantic[boldKey] as? Bool) == true
        typingAttributes.italic = (semantic[italicKey] as? Bool) == true
        typingAttributes.underline = (semantic[underlineKey] as? Bool) == true
        typingAttributes.strikethrough = (semantic[strikethroughKey] as? Bool) == true
        typingAttributes.textColor = semantic[textColorKey] as? RichTextColor
        return typingAttributes
    }

    /// Converts a semantic `AttributedString` to `NSAttributedString`,
    /// carrying only semantic attributes. Block-separator `\n` characters
    /// never carry *inline* attributes (bold/italic/underline/strikethrough/
    /// color) in the result — that is the invariant the rest of the engine
    /// and the HTML serializer depend on (a separator decorated with inline
    /// attributes would break `decode(encode(x)) == x`).
    ///
    /// How that invariant actually holds, measured: `RichTextAttributes.
    /// BlockStyleKey` declares `runBoundaries: .paragraph`, so Foundation
    /// normalizes `blockStyle` across a paragraph *including* its terminating
    /// newline, while inline attributes use ordinary (per-character) run
    /// boundaries. When a block's inline attributes are uniform right up to
    /// and including that boundary (the common case — no inline styling
    /// forces a split there), the terminating `"\n"` merges into the same
    /// `AttributedString` run as the preceding text, so this loop's `else`
    /// branch appends it via `semanticAttributes(of:)` and it legitimately
    /// keeps the block's `blockStyle` (see
    /// `separatorOnAnUnsplitTwoBlockDocumentCarriesOnlyBlockStyle`). But
    /// whenever the block's inline attributes differ from what's on either
    /// side of the newline (e.g. the block's text is bold and the newline
    /// itself never was), `AttributedString` splits the newline into a run of
    /// its own — and *this* branch below appends *any* lone `"\n"` run with
    /// an entirely empty attribute dictionary, discarding `blockStyle` too,
    /// not just the inline flags (see
    /// `separatorCharactersCarryNoInlineAttributesInTheProducedNSAttributedString`
    /// and the pinned styled-case test below it). Both outcomes are harmless:
    /// the read path (`attributedString(from:)`) re-derives `blockStyle` from
    /// paragraph boundaries in the raw string independent of what arrives on
    /// the newline, so round-tripping holds either way. Do not change this
    /// behavior to always keep or always drop `blockStyle` on the
    /// separator — it is unobserved by any caller and altering it risks
    /// perturbing the run-merging this comment only describes.
    static func nsAttributedString(from text: AttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for run in text.runs {
            let slice = text[run.range]
            let runString = String(slice.characters)
            if runString == "\n" {
                // A lone separator run: by construction (every block boundary
                // in this model is a bare, unattributed "\n") this never mixes
                // newline and non-newline characters in one run. Append it
                // with an empty attribute dictionary regardless of whatever
                // `semanticAttributes(of:)` might otherwise compute.
                result.append(NSAttributedString(string: runString))
            } else {
                result.append(NSAttributedString(string: runString, attributes: semanticAttributes(of: slice)))
            }
        }
        return result
    }

    /// Converts an `NSAttributedString` back to the semantic model, reading
    /// back only the known semantic keys with conditional casts. Any unknown
    /// key, or a known key with an unexpected value type, is silently
    /// ignored — never crashes, never guesses.
    ///
    /// `blockStyle` is legitimately paragraph-scoped (see the write path's
    /// doc comment on `runBoundaries: .paragraph`) — a newline that
    /// *terminates* a non-empty block keeps it, matching `RichTextHTML`. This
    /// is decided from the raw string's paragraph structure (`formsEmptyBlock`
    /// below), not from whatever the incoming `NSAttributedString` happens to
    /// carry on that newline — deliberately, since the write path above
    /// doesn't always leave `blockStyle` on a kept newline either (it drops
    /// every attribute, `blockStyle` included, whenever that newline was
    /// split into a run of its own), and a real text view's storage is a
    /// third, independent source that this read path must tolerate either
    /// way. But a newline that *constitutes its own (empty) paragraph* — one
    /// at the very start of the document, or immediately preceded by another
    /// newline — must come back bare, with no `blockStyle` at all, because
    /// `RichTextHTML.decode` leaves such a newline completely bare (an empty
    /// block can't hold a custom attribute on zero characters). A real text
    /// view stamps its typing attributes,
    /// `blockStyle` included, onto every inserted character — including a
    /// typed "\n" — so an empty block's newline can arrive here already
    /// (incorrectly) carrying one; `formsEmptyBlock(at:in:)` strips it back off
    /// regardless of what the incoming `NSAttributedString` happened to say.
    static func attributedString(from source: NSAttributedString) -> AttributedString {
        var result = AttributedString()
        let fullRange = NSRange(location: 0, length: source.length)
        guard fullRange.length > 0 else { return result }
        let fullString = source.string

        source.enumerateAttributes(in: fullRange, options: []) { attributes, range, _ in
            guard let swiftRange = Range(range, in: fullString) else {
                return
            }
            result += attributedRun(fullString[swiftRange], in: fullString, attributes: attributes)
        }
        // Normalize away any explicit black `textColor` this storage happened
        // to carry — e.g. a text view a consumer pre-populated before ever
        // going through the command layer's own normalization (Fix: black is
        // the absence of a color everywhere in the system, see
        // `EngineCore.normalizingDefaultColor`).
        return EngineCore.normalizingDefaultColor(result)
    }

    /// True for a newline that forms an empty paragraph entirely on its own:
    /// nothing precedes it, or the character immediately before it is itself a
    /// newline. Computed over the raw string, independent of whatever
    /// attributes the incoming `NSAttributedString` carries, so a polluted
    /// `blockStyle` on such a newline never survives.
    private static func formsEmptyBlock(at index: String.Index, in fullString: String) -> Bool {
        guard fullString[index] == "\n" else { return false }
        if index == fullString.startIndex {
            return true
        }
        return fullString[fullString.index(before: index)] == "\n"
    }

    // swiftlint:disable function_body_length
    /// Converts one attribute run of the source storage, `substring` within
    /// `fullString`, into its semantic `AttributedString` form.
    private static func attributedRun(
        _ substring: Substring,
        in fullString: String,
        attributes: [NSAttributedString.Key: Any]
    ) -> AttributedString {
        var result = AttributedString()

        let style = attributes[blockStyleKey] as? BlockStyle
        let bold = (attributes[boldKey] as? Bool) == true
        let italic = (attributes[italicKey] as? Bool) == true
        let underline = (attributes[underlineKey] as? Bool) == true
        let strikethrough = (attributes[strikethroughKey] as? Bool) == true
        let color = attributes[textColorKey] as? RichTextColor

        /// A real text view applies its typing attributes to every
        /// inserted character, including a typed "\n" — so one incoming
        /// run can mix newline and non-newline characters under the same
        /// (polluted) inline attributes, e.g. "abc\ndef" all bold. Split
        /// the run into maximal stretches sharing the same classification
        /// — non-newline, "kept" newline, or "empty-block" newline — so
        /// inline attributes never land on a separator and `blockStyle`
        /// never lands on an empty block's newline, regardless of how the
        /// source run happened to be shaped.
        func classify(_ index: String.Index) -> (isNewline: Bool, keepsBlockStyle: Bool) {
            guard substring[index] == "\n" else { return (false, true) }
            return (true, !formsEmptyBlock(at: index, in: fullString))
        }

        var chunkStart = substring.startIndex
        var chunkClass = classify(chunkStart)

        func flush(upTo end: String.Index) {
            guard chunkStart < end else {
                return
            }
            var piece = AttributedString(String(substring[chunkStart ..< end]))
            if let style, chunkClass.keepsBlockStyle {
                piece.blockStyle = style
            }
            if !chunkClass.isNewline {
                if bold {
                    piece.bold = true
                }
                if italic {
                    piece.italic = true
                }
                if underline {
                    piece.underline = true
                }
                if strikethrough {
                    piece.strikethrough = true
                }
                if let color {
                    piece.textColor = color
                }
            }
            result += piece
        }

        var index = substring.startIndex
        while index < substring.endIndex {
            let newClass = classify(index)
            if newClass != chunkClass {
                flush(upTo: index)
                chunkStart = index
                chunkClass = newClass
            }
            index = substring.index(after: index)
        }
        flush(upTo: substring.endIndex)
        return result
    }
    // swiftlint:enable function_body_length
}
