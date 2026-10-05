// EngineCore.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
import RichTextCore

/// The outcome of applying a command: the new document, where the selection
/// ended up, and the typing attributes that now apply at the caret.
struct EditResult: Equatable, Sendable {
    var text: AttributedString
    var selection: TextSelection
    var typingAttributes: TypingAttributes
}

/// All editing logic, as pure functions over `(AttributedString, TextSelection,
/// TypingAttributes)`. UIKit-free by design (M3 decision D1): every behavior the
/// editor has is testable here with `swift test`, and the platform adapters stay
/// thin enough to eyeball.
enum EngineCore {
    // MARK: - Ingest normalization

    /// Strips an explicit black `textColor` from every run in `text`. Black
    /// is treated as the absence of a text color everywhere in the system
    /// (`RichTextColor.black`): an explicit `#000000` would stay black in
    /// dark mode and become invisible against the background, whereas an
    /// absent color lets the theme's default adapt.
    ///
    /// `applyInline` (`EngineCore+Inline.swift`) already normalizes at the
    /// point of mutation for edits made *through* the engine, and
    /// `HTMLDecoder` normalizes on decode — but neither runs for a document
    /// that enters the engine some other way. This is the single, structural
    /// place that closes every such path: call it wherever a document is
    /// read or assigned into the engine from outside `apply(_:)`, so that no
    /// document the engine holds can ever carry an explicit black run,
    /// regardless of how it arrived. Currently called from
    /// `SemanticNSBridge.attributedString(from:)` (the storage read-back) and
    /// `UIKitEditorEngine.text`'s setter (a consumer assigning
    /// `RichTextEditor(text:)`'s binding directly) — a future ingest path
    /// should call this too rather than reinventing the rule.
    static func normalizingDefaultColor(_ text: AttributedString) -> AttributedString {
        var result = text
        for run in text.runs where run.textColor == .black {
            result[run.range].textColor = nil
        }
        return result
    }

    /// The UTF-16 offset of the first character with no block role, or `nil`
    /// when every character has one. A newline doesn't count: an empty
    /// block's separator can't hold a role (D13).
    static func firstRolelessOffset(in text: AttributedString) -> Int? {
        for run in text.runs where run.blockStyle == nil {
            if let index = text[run.range].characters.firstIndex(where: { $0 != "\n" }) {
                return TextOffsets.offset(of: index, in: text)
            }
        }
        return nil
    }

    /// `text` with `style` on every block that has a character with no block
    /// role (GitHub issue #73). UIKit can put text with no semantic attributes
    /// into storage: typing over a selection that empties a block resets the
    /// typing attributes before the character goes in.
    static func fillingMissingBlockStyle(_ text: AttributedString, with style: BlockStyle) -> AttributedString {
        guard firstRolelessOffset(in: text) != nil else { return text }
        var result = text
        for block in BlockScanner.blocks(of: text) where !block.isEmpty {
            let range = TextOffsets.range(TextSelection(location: block.location, length: block.length), in: text)
            if text[range].runs.contains(where: { $0.blockStyle == nil }) {
                result[range].blockStyle = style
            }
        }
        return result
    }

    /// Everything the engine requires of a document that arrives from outside
    /// the command layer: LF block separators, no explicit black `textColor`,
    /// and a block role on every character. Text with no role gets
    /// `missingBlockStyle`: a paragraph, which is what the encoder writes for
    /// it, unless the caller knows better. Every path into
    /// `UIKitEditorEngine.semanticText` that did not come from `EngineCore` itself (the public `text` setter, the
    /// initializer's pre-populated text view, and `synchronizeFromTextView()`
    /// after UIKit edits storage directly) goes through here, so a new ingest
    /// path has one function to call rather than a rule to remember.
    ///
    /// Returns `nil` when `text` already complies, so the per-keystroke
    /// `synchronizeFromTextView()` path can tell without comparing documents.
    /// `selection` is mapped from `text`'s UTF-16 offsets to the result's.
    static func normalizedIngest(
        _ text: AttributedString,
        selection: TextSelection,
        missingBlockStyle: BlockStyle = .paragraph
    ) -> (text: AttributedString, selection: TextSelection)? {
        let hasCR = LineEndings.needsNormalizing(text.unicodeScalars)
        let filled = fillingMissingBlockStyle(LineEndings.normalized(text), with: missingBlockStyle)
        let normalized = bareSeparators(in: normalizingDefaultColor(filled))
        guard normalized != text else { return nil }
        let mappedSelection = hasCR ? LineEndings.selection(selection, mappedThrough: text) : selection
        return (normalized, mappedSelection)
    }

    // MARK: - Applying commands

    /// Applies a command and returns the resulting document, selection, and
    /// typing attributes. Pure: nothing is mutated in place.
    static func apply(
        _ command: FormatCommand,
        to text: AttributedString,
        selection: TextSelection,
        typingAttributes: TypingAttributes
    ) -> EditResult {
        switch command {
        case .toggleBold:
            applyInline(.flag(.bold), to: text, selection: selection, typingAttributes: typingAttributes)
        case .toggleItalic:
            applyInline(.flag(.italic), to: text, selection: selection, typingAttributes: typingAttributes)
        case .toggleUnderline:
            applyInline(.flag(.underline), to: text, selection: selection, typingAttributes: typingAttributes)
        case .toggleStrikethrough:
            applyInline(.flag(.strikethrough), to: text, selection: selection, typingAttributes: typingAttributes)
        case let .setTextColor(color):
            applyInline(.color(color), to: text, selection: selection, typingAttributes: typingAttributes)
        case let .setBlockStyle(style):
            applyBlock(.setStyle(style), to: text, selection: selection, typingAttributes: typingAttributes)
        case let .toggleHeading(level):
            applyBlock(.toggleHeading(level), to: text, selection: selection, typingAttributes: typingAttributes)
        case let .toggleList(kind):
            applyBlock(.toggleList(kind), to: text, selection: selection, typingAttributes: typingAttributes)
        }
    }

    // MARK: - Reading state

    /// The formatting of the current selection. For a caret, inline state comes
    /// from `typingAttributes` (there are no selected characters to read).
    static func formatState(
        of text: AttributedString,
        selection: TextSelection,
        typingAttributes: TypingAttributes
    ) -> FormatState {
        var state = FormatState()
        state.blockStyle = blockStyleState(of: text, selection: selection, typingAttributes: typingAttributes)

        guard !selection.isCollapsed else {
            for flag in InlineFlag.allCases {
                setState(flag, typingAttributes[flag] ? .on : .off, on: &state)
            }
            state.textColor = typingAttributes.textColor
            state.isTextColorMixed = false
            return state
        }

        let range = TextOffsets.range(selection, in: text)
        var flagCounts: [InlineFlag: (on: Int, off: Int)] = [:]
        var colors: Set<RichTextColor?> = []
        var runCount = 0

        for run in text[range].runs {
            let slice = text[run.range]
            // Block-separator newlines ("\n" joining paragraphs/headings/list
            // items) are runs of their own but carry no inline attributes by
            // construction (both `Sem.doc` and `HTMLDecoder` join blocks with
            // a bare `AttributedString("\n")`). If counted, a run of all-off
            // flags on the separator would make any multi-block selection
            // report `.mixed` even when every actual character is uniformly
            // styled — e.g. two fully-bold paragraphs. Skip them so a block
            // boundary alone never manufactures "mixed" state. Do not
            // "simplify" this away.
            if slice.characters.allSatisfy({ $0 == "\n" }) {
                continue
            }
            runCount += 1
            for flag in InlineFlag.allCases {
                var counts = flagCounts[flag] ?? (0, 0)
                if flagValue(flag, in: slice) {
                    counts.on += 1
                } else {
                    counts.off += 1
                }
                flagCounts[flag] = counts
            }
            colors.insert(slice.textColor)
        }

        for flag in InlineFlag.allCases {
            let counts = flagCounts[flag] ?? (0, 0)
            let value: TriState = if runCount == 0 || counts.on == 0 {
                .off
            } else if counts.off == 0 {
                .on
            } else {
                .mixed
            }
            setState(flag, value, on: &state)
        }

        if colors.count > 1 {
            state.isTextColorMixed = true
            state.textColor = nil
        } else {
            state.isTextColorMixed = false
            // `colors` is `Set<RichTextColor?>`, so `colors.first` is
            // `Optional<RichTextColor?>` and `?? nil` flattens it: no runs
            // (including "every run was a skipped newline") or the sole
            // element being `nil` both yield `nil`; a sole `.some(x)` yields
            // `x`. Do not "simplify" this into `colors.first ?? nil ?? nil`
            // or similar — the double-optional collapse is intentional.
            state.textColor = colors.first ?? nil
        }
        return state
    }

    /// The typing attributes that apply at a caret, derived from the document:
    /// the character *before* the caret (standard editor behavior), falling back
    /// to the character after it at the start of a block or document.
    static func typingAttributes(at selection: TextSelection, in text: AttributedString) -> TypingAttributes {
        var attributes = TypingAttributes()
        guard !text.characters.isEmpty else { return attributes }

        let caret = TextOffsets.index(at: selection.lowerBound, in: text)
        var source: AttributedString.Index?
        if caret > text.startIndex {
            let before = text.index(beforeCharacter: caret)
            if text.characters[before] != "\n" {
                source = before
            }
        }
        if source == nil, caret < text.endIndex, text.characters[caret] != "\n" {
            source = caret
        }
        // If both neighbors are newlines (or absent), the caret sits in an
        // empty block flanked by separators — e.g. "abc\n\ndef" with the
        // caret in the middle. There is no inline-attribute source to derive
        // from, so `attributes` is returned clean. This is intended: a fresh
        // empty block starts unstyled rather than inheriting from whatever
        // came before or after it.
        guard let source else { return attributes }

        let slice = text[source ..< text.index(afterCharacter: source)]
        for flag in InlineFlag.allCases {
            attributes[flag] = flagValue(flag, in: slice)
        }
        attributes.textColor = slice.textColor
        // `blockStyle` stays nil: a non-empty block carries its own marker, and
        // an empty one has nothing to derive from (M3 decision D13).
        return attributes
    }

    /// The typing attributes to use after the caret/selection moves, carrying
    /// forward a *pending* block style (D13) only when it still describes the
    /// same empty block.
    ///
    /// A pending style is per-empty-block intent, not global: if the caret was
    /// pending `.heading(1)` in one empty block and the user taps into a
    /// *different* empty block, that intent must not leak there — the pending
    /// style is dropped. It survives only when the caret is re-collapsed onto
    /// the exact same empty block it was in before.
    ///
    /// Everything else is re-derived from `text` via `typingAttributes(at:in:)`
    /// — inline flags/color never carry over from `previous`.
    ///
    /// Caveat: `text` is the caller's *current* document. If it mutated the
    /// document between `previousSelection` and `selection` (insertion,
    /// deletion, block split/merge), `previousSelection` is being read against
    /// the *new* geometry, not the geometry it was actually captured against.
    /// Callers that mutate around a selection change should recompute
    /// `previousSelection` in the new document's offsets first.
    static func typingAttributes(
        movingTo selection: TextSelection,
        in text: AttributedString,
        previous: TypingAttributes,
        previouslyAt previousSelection: TextSelection
    ) -> TypingAttributes {
        var attributes = typingAttributes(at: selection, in: text)

        guard let pending = previous.blockStyle, selection.isCollapsed else { return attributes }
        guard let newBlock = BlockScanner.blocks(of: text, intersecting: selection).first, newBlock.isEmpty else {
            return attributes
        }
        guard let previousBlock = BlockScanner.blocks(of: text, intersecting: previousSelection).first,
              previousBlock.location == newBlock.location
        else {
            return attributes
        }

        attributes.blockStyle = pending
        return attributes
    }

    // MARK: - Attribute access helpers

    static func flagValue(_ flag: InlineFlag, in slice: AttributedSubstring) -> Bool {
        switch flag {
        case .bold: slice.bold == true
        case .italic: slice.italic == true
        case .underline: slice.underline == true
        case .strikethrough: slice.strikethrough == true
        }
    }

    /// Sets (or, with `nil`, **removes**) an inline flag. Removal matters:
    /// leaving `false` behind would break model equality against freshly
    /// decoded documents and add noise the encoder has to ignore.
    static func setFlag(
        _ flag: InlineFlag,
        _ value: Bool?,
        in text: inout AttributedString,
        range: Range<AttributedString.Index>
    ) {
        switch flag {
        case .bold: text[range].bold = value
        case .italic: text[range].italic = value
        case .underline: text[range].underline = value
        case .strikethrough: text[range].strikethrough = value
        }
    }

    private static func setState(_ flag: InlineFlag, _ value: TriState, on state: inout FormatState) {
        switch flag {
        case .bold: state.bold = value
        case .italic: state.italic = value
        case .underline: state.underline = value
        case .strikethrough: state.strikethrough = value
        }
    }

    private static func blockStyleState(
        of text: AttributedString,
        selection: TextSelection,
        typingAttributes: TypingAttributes
    ) -> BlockStyle? {
        let blocks = BlockScanner.blocks(of: text, intersecting: selection)
        if selection.isCollapsed, let pending = typingAttributes.blockStyle,
           blocks.first?.isEmpty ?? true
        {
            return pending
        }
        guard let first = blocks.first else { return .paragraph }
        return blocks.allSatisfy { $0.style == first.style } ? first.style : nil
    }
}
