// MarkdownInlineEncoder+Flanking.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation

/// Where `MarkdownInlineEncoder` puts `separator` so every delimiter run
/// parses: CommonMark's flanking rules, plus what Foundation's parser does
/// differently.
extension MarkdownInlineEncoder {
    /// The closing and opening delimiters at one segment boundary, with
    /// `separator` wherever a delimiter run would not parse.
    ///
    /// CommonMark only treats a run as closing when it is *right-flanking*
    /// (not after whitespace; after punctuation, only if followed by
    /// whitespace or punctuation), and as opening when it is *left-flanking*
    /// (the mirror image). An opening run mid-word is both, so it gets a
    /// separator before it too. Two runs of one character that touch merge
    /// into one. The separator's `<` and `>` are punctuation, so it fixes either
    /// side of a run without adding text. Crossing marks are what put a run
    /// next to whitespace: in `**a *b** c*`, bold ends inside italic, so
    /// italic closes and reopens there, just before the space.
    ///
    /// Each separator only turns a neighbor into punctuation, so adding one
    /// can break another run's flanking; the loop repeats until every run
    /// parses. It ends, since each pass adds a separator to a gap that had
    /// none.
    static func delimiters(
        closing: String,
        opening: [String],
        after previous: Character?,
        before body: String
    ) -> String {
        let runs = sameCharacterRuns(closing).map { (text: $0, closes: true) }
            + opening.map { (text: $0, closes: false) }
        guard !runs.isEmpty else {
            return ""
        }
        // `separated[i]` puts a separator just before `runs[i]`; the last
        // entry is the gap after the final run.
        var separated = Array(repeating: false, count: runs.count + 1)
        for index in runs.indices.dropFirst() where runs[index - 1].text.last == runs[index].text.first {
            separated[index] = true
        }
        var changed = true
        while changed {
            changed = false
            for (index, run) in runs.enumerated() {
                let delimiter = run.text.first
                let before = neighbor(
                    separated: separated[index],
                    delimiter: index > 0 ? runs[index - 1].text.first : nil,
                    text: previous,
                    of: delimiter
                )
                let after = neighbor(
                    separated: separated[index + 1],
                    delimiter: index + 1 < runs.count ? runs[index + 1].text.first : nil,
                    text: body.first,
                    of: delimiter
                )
                if run.closes, before.isWhitespace || (before.isPunctuation && after.isWord) {
                    // A closing run never follows whitespace in practice:
                    // the mark closing here ends on `previous`, and marks are
                    // pulled off whitespace. Kept so the rule stays whole.
                    separated[before.isWhitespace ? index : index + 1] = true
                    changed = true
                } else if !run.closes, after.isWhitespace || (after.isPunctuation && before.isWord)
                    || (after.isWord && before.isWord)
                {
                    // Mid-word (`x*q`), an opening run can also close, and
                    // may close an outer mark still open: in `***p* x*q***`
                    // it ends the bold. Punctuation before it rules that out.
                    separated[after.isWhitespace ? index + 1 : index] = true
                    changed = true
                }
            }
        }
        var out = ""
        for (index, run) in runs.enumerated() {
            if separated[index] {
                out += separator
            }
            out += run.text
        }
        if separated[runs.count] {
            out += separator
        }
        return out
    }

    /// How a delimiter run sees the character beside it.
    private struct Neighbor {
        var isWhitespace = false
        var isPunctuation = false
        var isWord = false
    }

    /// The neighbor across one gap: the separator, another delimiter run,
    /// or text (`nil` text is a line edge, which counts as whitespace).
    ///
    /// A delimiter run of the other kind counts as both punctuation and a
    /// word character. Foundation's parser, with its GFM strikethrough, reads
    /// it inconsistently: `x**~~b~~**y` is bold but `x**~~"b"~~**y` is not,
    /// and `**(a)**~~b~~` is not bold though `**(a)**\~` is. Reading it both
    /// ways puts a separator outside a `**~~` pair that touches a word, which
    /// parses in every case.
    private static func neighbor(
        separated: Bool,
        delimiter: Character?,
        text: Character?,
        of _: Character?
    ) -> Neighbor {
        if separated {
            return Neighbor(isPunctuation: true)
        }
        if delimiter != nil {
            return Neighbor(isPunctuation: true, isWord: true)
        }
        guard let text else {
            return Neighbor(isWhitespace: true)
        }
        return Neighbor(isWhitespace: text.isWhitespace, isPunctuation: isPunctuation(text), isWord: isWord(text))
    }

    /// `***~~` as `["***", "~~"]`: runs of one delimiter character, which is
    /// how CommonMark scans them.
    static func sameCharacterRuns(_ delimiters: String) -> [String] {
        var runs: [String] = []
        for character in delimiters {
            if runs.last?.last == character {
                runs[runs.count - 1].append(character)
            } else {
                runs.append(String(character))
            }
        }
        return runs
    }

    // CommonMark versions disagree on non-ASCII symbols (emoji, `→`, `€`):
    // the parser in Foundation reads them as neither punctuation nor
    // whitespace, while CommonMark 0.31 reads them as punctuation. So such a
    // symbol counts as both here, and gets whichever separator either
    // reading needs. Reading a character both ways only ever adds a
    // harmless separator.

    /// Punctuation under some CommonMark version: anything that is neither
    /// whitespace, a letter nor a digit.
    private static func isPunctuation(_ character: Character?) -> Bool {
        guard let character else {
            return false
        }
        return !character.isWhitespace && !character.isLetter && !character.isNumber
    }

    /// Not punctuation under some CommonMark version: anything but
    /// whitespace, ASCII punctuation and Unicode punctuation (P*).
    private static func isWord(_ character: Character?) -> Bool {
        guard let character, !character.isWhitespace else {
            return false
        }
        if character.isASCII {
            return character.isLetter || character.isNumber
        }
        return !character.isPunctuation
    }
}
