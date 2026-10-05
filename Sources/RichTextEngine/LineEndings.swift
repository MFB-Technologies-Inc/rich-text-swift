// LineEndings.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation

/// The one definition of which line endings become the model's `"\n"` block
/// separator (`BlockScanner`): CRLF, lone CR, U+2029 PARAGRAPH SEPARATOR
/// (what Cocoa text uses between paragraphs) and U+0085 NEXT LINE.
///
/// U+2028 LINE SEPARATOR is left alone: it breaks a line *inside* a
/// paragraph, and the model has no soft break to map it to. Promoting it to
/// `"\n"` would split one block into two.
///
/// Every ingest path that sees
/// raw text (`EngineCore.normalizedIngest`, plain-text paste in
/// `RichTextTextView`) calls into this type, so the rule cannot drift between
/// them.
///
/// `HTMLTokenizer` keeps its own byte-level CR handling on purpose: that is
/// the HTML input-stream preprocessing step, fixed by the HTML spec, and it
/// runs on UTF-8 bytes in `RichTextCore`, below this module.
package enum LineEndings {
    /// Applies the rule to one scalar. `previousWasCR` carries state across
    /// calls, so a CRLF split between two attribute runs still collapses.
    /// Returns the scalar to emit, or `nil` for the LF half of a CRLF.
    static func normalize(_ scalar: Unicode.Scalar, previousWasCR: inout Bool) -> Unicode.Scalar? {
        defer { previousWasCR = scalar == "\r" }
        switch scalar {
        case "\n" where previousWasCR:
            return nil
        case "\r", "\u{2029}", "\u{0085}":
            return "\n"
        default:
            return scalar
        }
    }

    /// Whether `scalars` contains anything the rule would change.
    ///
    /// Tests scalars, not `Character`s: Swift `String` comparison is
    /// grapheme-based and CRLF is a single grapheme cluster, so
    /// `"a\r\nb".contains("\r")` is `false`.
    static func needsNormalizing(_ scalars: some Sequence<Unicode.Scalar>) -> Bool {
        scalars.contains { $0 == "\r" || $0 == "\u{2029}" || $0 == "\u{0085}" }
    }

    /// Converts every line ending the rule covers in a plain string to LF.
    package static func normalized(_ string: String) -> String {
        guard needsNormalizing(string.unicodeScalars) else { return string }
        var previousWasCR = false
        var result = String.UnicodeScalarView()
        for scalar in string.unicodeScalars {
            if let out = normalize(scalar, previousWasCR: &previousWasCR) {
                result.append(out)
            }
        }
        return String(result)
    }

    /// Converts every line ending the rule covers to LF while retaining run
    /// attributes.
    /// Processes whole runs rather than appending a fragment for every
    /// newline; CRLF can span two attribute runs.
    package static func normalized(_ text: AttributedString) -> AttributedString {
        guard needsNormalizing(text.unicodeScalars) else {
            return text
        }

        var result = AttributedString()
        var previousWasCR = false
        for run in text.runs {
            // `characters` can include both scalars of a CRLF in the second
            // run and none in the first, so read each run by Unicode scalars.
            var normalized = String.UnicodeScalarView()
            for scalar in text[run.range].unicodeScalars {
                if let out = normalize(scalar, previousWasCR: &previousWasCR) {
                    normalized.append(out)
                }
            }
            if !normalized.isEmpty {
                result.append(AttributedString(String(normalized), attributes: run.attributes))
            }
        }
        return result
    }

    /// Maps both UTF-16 selection endpoints in `text` onto `normalized(text)`.
    /// Only a dropped scalar shifts later offsets; every replacement is one
    /// UTF-16 unit, like the scalar it replaces.
    static func selection(_ selection: TextSelection, mappedThrough text: AttributedString) -> TextSelection {
        let start = selection.lowerBound
        let end = selection.upperBound
        var rawOffset = 0
        var removedBeforeStart = 0
        var removedBeforeEnd = 0
        var previousWasCR = false
        for scalar in text.unicodeScalars {
            if normalize(scalar, previousWasCR: &previousWasCR) == nil {
                if rawOffset < start {
                    removedBeforeStart += scalar.utf16.count
                }
                if rawOffset < end {
                    removedBeforeEnd += scalar.utf16.count
                }
            }
            rawOffset += scalar.utf16.count
        }
        let mappedStart = start - removedBeforeStart
        return TextSelection(location: mappedStart, length: end - removedBeforeEnd - mappedStart)
    }
}
