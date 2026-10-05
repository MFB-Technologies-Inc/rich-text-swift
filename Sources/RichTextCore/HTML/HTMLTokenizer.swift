// HTMLTokenizer.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation

extension UInt8 {
    var isASCIILetter: Bool {
        (self | 0x20) &- UInt8(ascii: "a") < 26
    }

    var isASCIINumber: Bool {
        self &- UInt8(ascii: "0") < 10
    }
}

// All raw bytes being decoded into String is known to be
// valid UTF-8 because it all came from valid Strings
// swiftlint:disable optional_data_string_conversion

/// A tolerant, hand-rolled HTML tokenizer.
///
/// Turns a raw HTML string into a flat stream of `HTMLToken`s. It never throws
/// and never crashes: malformed, unterminated, or ambiguous input degrades
/// gracefully (a stray `<` becomes literal text, an unterminated tag at EOF is
/// dropped, malformed attributes are skipped).
enum HTMLTokenizer {
    // swiftlint:disable:next function_body_length
    static func tokenize(_ html: String) -> [HTMLToken] {
        let bytes = Array(html.utf8)
        let count = bytes.count
        var index = 0
        var tokens: [HTMLToken] = []
        // Start of the pending text run. Text is always a contiguous slice of
        // `bytes`, so it is decoded in place rather than copied into a buffer.
        var textStart = 0

        /// Emits the text run `bytes[textStart ..< index]`, if there is one.
        func flush() {
            if textStart < index {
                let text = string(bytes[textStart ..< index])
                tokens.append(.text(HTMLEscaping.decodeEntities(text)))
            }
        }

        let commentPrefixBytes = Array("<!--".utf8)
        let commentPostfixBytes = Array("-->".utf8)

        while index < count {
            if bytes[index] == UInt8(ascii: "<") {
                // comment: <!-- ... -->
                if hasPrefix(bytes, index, commentPrefixBytes) {
                    flush()
                    index = skipUntil(bytes, index + 4, commentPostfixBytes, advance: 3, count)
                    textStart = index
                    continue
                }
                // declaration (<!doctype ...>) or processing instruction (<? ... ?>)
                let isDeclaration = isByte(bytes, index + 1, count, UInt8(ascii: "!"))
                    || isByte(bytes, index + 1, count, UInt8(ascii: "?"))
                if isDeclaration {
                    flush()
                    index = skipUntilChar(bytes, index + 1, UInt8(ascii: ">"), count)
                    textStart = index
                    continue
                }
                // end tag: </name>
                if isByte(bytes, index + 1, count, UInt8(ascii: "/")) {
                    if let (name, next) = scanEndTag(bytes, index, count) {
                        flush()
                        tokens.append(.endTag(name: name))
                        index = next
                        textStart = index
                        continue
                    }
                    // scanEndTag returns nil only on an unterminated tag at EOF:
                    // keep the preceding text, drop the tag.
                    flush()
                    index = count
                    textStart = count
                    continue
                }
                // start tag: <name ...>
                if index + 1 < count, isNameStart(bytes[index + 1]), isStandalone(bytes, index + 1, count) {
                    if let (tok, next) = scanStartTag(bytes, index, count) {
                        flush()
                        tokens.append(tok)
                        index = next
                        textStart = index
                        continue
                    }
                    // scanStartTag returns nil only on an unterminated tag at EOF:
                    // keep the preceding text, drop the tag.
                    flush()
                    index = count
                    textStart = count
                    continue
                }
                // stray '<' — literal text, left in the pending run
            }
            index += 1
        }
        flush()
        return tokens
    }

    // MARK: - Scanning helpers

    /// True when the ASCII byte at `index` is a whole grapheme cluster on its
    /// own. A following combining mark (`a\u{301}`, `>\u{338}`) joins it into a
    /// single non-ASCII `Character`, which is never a delimiter or a name
    /// letter. A preceding Prepend scalar (`\u{600}<`) is deliberately not
    /// checked: the byte stays a delimiter, as it is for a browser.
    private static func isStandalone(_ bytes: [UInt8], _ index: Int, _ count: Int) -> Bool {
        let next = index + 1
        // Two ASCII scalars never join, except CR LF, and the scanners treat
        // both of those as whitespace either way.
        guard next < count, bytes[next] >= 0x80 else { return true }
        var end = next + 1
        while end < count, bytes[end] & 0xC0 == 0x80 {
            end += 1
        }
        return String(decoding: bytes[index ..< end], as: UTF8.self).count == 2
    }

    /// True when `index` is in range and holds `byte` as a whole grapheme cluster.
    private static func isByte(_ bytes: [UInt8], _ index: Int, _ count: Int, _ byte: UInt8) -> Bool {
        index < count && bytes[index] == byte && isStandalone(bytes, index, count)
    }

    /// Returns true if `bytes` starting at `start` matches every byte of `prefix`.
    private static func hasPrefix(_ bytes: [UInt8], _ start: Int, _ prefix: [UInt8]) -> Bool {
        guard start + prefix.count <= bytes.count else { return false }
        for offset in 0 ..< prefix.count where bytes[start + offset] != prefix[offset] {
            return false
        }
        // Only the last byte can join with what follows; the rest are followed by ASCII.
        return isStandalone(bytes, start + prefix.count - 1, bytes.count)
    }

    /// Scans forward from `start` until `marker` is found, then returns the index
    /// just past it (`+ advance`). If the marker never appears, returns `count`
    /// (EOF), consuming the rest of the input.
    private static func skipUntil(
        _ bytes: [UInt8],
        _ start: Int,
        _ marker: [UInt8],
        advance: Int,
        _ count: Int
    ) -> Int {
        var index = start
        while index < count {
            if hasPrefix(bytes, index, marker) {
                return index + advance
            }
            index += 1
        }
        return count
    }

    /// Scans forward from `start` until `byte` is found, returning the index just
    /// past it. If never found, returns `count` (EOF).
    private static func skipUntilChar(_ bytes: [UInt8], _ start: Int, _ byte: UInt8, _ count: Int) -> Int {
        var index = start
        while index < count {
            if bytes[index] == byte, isStandalone(bytes, index, count) {
                return index + 1
            }
            index += 1
        }
        return count
    }

    /// A valid tag-name start byte (ASCII letter).
    private static func isNameStart(_ byte: UInt8) -> Bool {
        byte.isASCIILetter
    }

    /// A valid tag/attribute-name continuation byte.
    private static func isNameChar(_ byte: UInt8) -> Bool {
        (byte.isASCIILetter || byte.isASCIINumber) || byte == UInt8(ascii: "-") || byte == UInt8(ascii: "_") || byte ==
            UInt8(ascii: ":")
    }

    /// True when the byte at `index` ends an attribute name: whitespace, `=`, `>`, or `/`.
    private static func isAttributeNameEnd(_ bytes: [UInt8], _ index: Int, _ count: Int) -> Bool {
        let byte = bytes[index]
        return (isSpace(byte) || byte == UInt8(ascii: "=") || byte == UInt8(ascii: ">") || byte == UInt8(ascii: "/"))
            && isStandalone(bytes, index, count)
    }

    private static func isSpace(_ byte: UInt8) -> Bool {
        byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\t") || byte == UInt8(ascii: "\n") || byte ==
            UInt8(ascii: "\r") || byte == UInt8(ascii: "\u{0C}")
    }

    /// Scans an end tag `</name ...>` beginning at `start` (the `<`).
    /// Returns the lowercased name and the index just past the closing `>`,
    /// or `nil` if there is no closing `>` before EOF (→ treat `<` as literal).
    private static func scanEndTag(_ bytes: [UInt8], _ start: Int, _ count: Int) -> (name: String, next: Int)? {
        var index = start + 2 // skip "</"
        let startOfName = index
        while index < count, isNameChar(bytes[index]), isStandalone(bytes, index, count) {
            index += 1
        }
        let endOfName = index
        // consume anything up to '>'
        while index < count, !isByte(bytes, index, count, UInt8(ascii: ">")) {
            index += 1
        }
        guard index < count else {
            return nil
        }
        return (String(decoding: bytes[startOfName ..< endOfName], as: UTF8.self).lowercased(), index + 1)
    }

    /// Scans a start tag `<name attr=... />` beginning at `start` (the `<`).
    /// Returns the token and the index just past the closing `>`, or `nil` if
    /// there is no closing `>` before EOF (→ treat `<` as literal, drop tag).
    private static func scanStartTag(
        _ bytes: [UInt8],
        _ start: Int,
        _ count: Int
    ) -> (token: HTMLToken, next: Int)? {
        var index = start + 1 // skip "<"
        let startOfName = index
        while index < count, isNameChar(bytes[index]), isStandalone(bytes, index, count) {
            index += 1
        }
        let lowerName = String(decoding: bytes[startOfName ..< index], as: UTF8.self).lowercased()

        var attributes: [String: String] = [:]
        var selfClosing = false

        while index < count {
            // skip whitespace between attributes
            while index < count, isSpace(bytes[index]), isStandalone(bytes, index, count) {
                index += 1
            }
            // ran off the end with no '>'
            guard index < count else {
                return nil
            }

            if isByte(bytes, index, count, UInt8(ascii: ">")) {
                index += 1
                // Void-element classification lives in `HTMLTagClasses` — the single
                // source of truth shared with the decoder, so this and the decoder's
                // block/skip-content handling cannot drift apart.
                if HTMLTagClasses.void.contains(lowerName) {
                    selfClosing = true
                }
                return (.startTag(name: lowerName, attributes: attributes, selfClosing: selfClosing), index)
            }

            if isByte(bytes, index, count, UInt8(ascii: "/")) {
                // possible self-closing slash; look for '>'
                selfClosing = true
                index += 1
                continue
            }

            guard let attribute = scanAttribute(bytes, index, count) else {
                return nil
            }
            index = attribute.next
            if let attributeName = attribute.name {
                attributes[attributeName] = attribute.value
            }
        }

        return nil // reached EOF without a closing '>'
    }

    /// One attribute read out of a start tag.
    private struct ScannedAttribute {
        /// `nil` when the scan skipped a byte that cannot start an
        /// attribute, rather than reading a name/value pair.
        var name: String?
        var value: String
        var next: Int
    }

    /// Scans one `name`, `name=value`, or `name="value"` pair beginning at
    /// `start`. Returns `nil` only at EOF with the tag still unterminated.
    private static func scanAttribute(_ bytes: [UInt8], _ start: Int, _ count: Int) -> ScannedAttribute? {
        var index = start
        let startOfName = index
        while index < count, !isAttributeNameEnd(bytes, index, count) {
            index += 1
        }

        if startOfName == index {
            // Not a valid attribute start (e.g. stray byte); skip it to avoid stalling.
            if index < count {
                index += 1
            }
            return ScannedAttribute(name: nil, value: "", next: index)
        }

        let endOfName = index

        // skip whitespace after name
        while index < count, isSpace(bytes[index]), isStandalone(bytes, index, count) {
            index += 1
        }

        guard isByte(bytes, index, count, UInt8(ascii: "=")) else {
            // bare/valueless attribute
            return ScannedAttribute(
                name: string(bytes[startOfName ..< endOfName]).lowercased(),
                value: "",
                next: index
            )
        }
        index += 1
        // skip whitespace after '='
        while index < count, isSpace(bytes[index]), isStandalone(bytes, index, count) {
            index += 1
        }
        guard index < count, let (value, next) = scanAttributeValue(bytes, index, count) else {
            return nil
        }
        return ScannedAttribute(
            name: string(bytes[startOfName ..< endOfName]).lowercased(),
            value: HTMLEscaping.decodeEntities(value),
            next: next
        )
    }

    /// Reads an attribute value beginning at `start`, which must be in bounds:
    /// quoted, or unquoted up to the next whitespace or `>`. Returns `nil` on
    /// a quoted value left unterminated at EOF.
    private static func scanAttributeValue(
        _ bytes: [UInt8],
        _ start: Int,
        _ count: Int
    ) -> (value: String, next: Int)? {
        var index = start
        let quote = bytes[index]
        if quote == UInt8(ascii: "\"") || quote == UInt8(ascii: "'"), isStandalone(bytes, index, count) {
            index += 1
            let startOfValue = index
            while index < count, !isByte(bytes, index, count, quote) {
                index += 1
            }
            // unterminated quoted value at EOF
            guard index < count else {
                return nil
            }
            let endOfValue = index
            index += 1 // consume closing quote
            return (string(bytes[startOfValue ..< endOfValue]), index)
        } else {
            let startOfValue = index
            // unquoted value: run until whitespace or '>'
            while index < count,
                  !((isSpace(bytes[index]) || bytes[index] == UInt8(ascii: ">")) && isStandalone(bytes, index, count))
            {
                index += 1
            }
            return (string(bytes[startOfValue ..< index]), index)
        }
    }
}

// MARK: - Content decoding

extension HTMLTokenizer {
    /// Decodes `slice` as UTF-8, turning CR LF and bare CR into LF the way HTML
    /// input preprocessing does. Used for everything that leaves the tokenizer
    /// as content (text, attribute names and values), so no consumer sees a
    /// literal CR. Entities are decoded after this, so `&#13;` still yields CR.
    private static func string(_ slice: ArraySlice<UInt8>) -> String {
        guard slice.contains(UInt8(ascii: "\r")) else {
            return String(decoding: slice, as: UTF8.self)
        }
        var normalized = [UInt8]()
        normalized.reserveCapacity(slice.count)
        var index = slice.startIndex
        while index < slice.endIndex {
            if slice[index] == UInt8(ascii: "\r") {
                normalized.append(UInt8(ascii: "\n"))
                if index + 1 < slice.endIndex, slice[index + 1] == UInt8(ascii: "\n") {
                    index += 1
                }
            } else {
                normalized.append(slice[index])
            }
            index += 1
        }
        return String(decoding: normalized, as: UTF8.self)
    }
}

// swiftlint:enable optional_data_string_conversion
