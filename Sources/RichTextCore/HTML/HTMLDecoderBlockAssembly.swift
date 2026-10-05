// HTMLDecoderBlockAssembly.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation

extension HTMLDecoder {
    /// A finalized block's text, as runs that each carry their inline
    /// attributes, plus the block's style. `Builder.finish()` assembles every
    /// block into one `AttributedString`.
    struct Block {
        var runs: [(text: String, attributes: AttributeContainer)]
        var style: BlockStyle
    }
}

extension HTMLDecoder.Builder {
    static func buildBlock(_ runs: [HTMLDecoder.Run], style: BlockStyle) -> HTMLDecoder.Block {
        HTMLDecoder.Block(runs: styledRuns(collapseWhitespace(runs)), style: style)
    }

    /// Collapses runs of ASCII whitespace to a single space, then trims
    /// the block's leading and trailing spaces. A soft line break (U+2028)
    /// and U+00A0 are not collapsible, and are never trimmed.
    ///
    /// The collapsed space keeps the formatting of the first whitespace
    /// character it replaces, even when the whitespace spans several runs.
    private static func collapseWhitespace(_ runs: [HTMLDecoder.Run]) -> [HTMLDecoder.Run] {
        var collapsed: [HTMLDecoder.Run] = []
        collapsed.reserveCapacity(runs.count)
        // Starting as if after a space drops the block's leading whitespace,
        // which is what trimming its start would do.
        var prevSpace = true
        for run in runs {
            let text = if run.text.utf8.allSatisfy({ $0 < 0x80 }) {
                collapseASCII(run.text, &prevSpace)
            } else {
                collapseByCharacter(run.text, &prevSpace)
            }
            collapsed.append(HTMLDecoder.Run(text: text, state: run.state))
        }
        // Collapsing leaves at most one trailing space. Remove that scalar
        // alone: removing the last `Character` could take a preceding scalar
        // that the space joined in the rebuilt string.
        if prevSpace, let last = collapsed.lastIndex(where: { !$0.text.isEmpty }) {
            collapsed[last].text.unicodeScalars.removeLast()
        }
        return collapsed
    }

    /// In ASCII text every byte is its own character, except CR LF, which is
    /// whitespace either way, so bytes can be classified directly.
    private static func collapseASCII(_ text: String, _ prevSpace: inout Bool) -> String {
        // first check if any collapse is needed to avoid needless allocation
        var scanPrevSpace = prevSpace
        var needsCollapse = false
        for byte in text.utf8 {
            if HTMLDecoder.isCollapsibleWhitespaceByte(byte) {
                if scanPrevSpace || byte != 0x20 {
                    needsCollapse = true
                    break
                }
                scanPrevSpace = true
            } else {
                scanPrevSpace = false
            }
        }
        guard needsCollapse else {
            prevSpace = scanPrevSpace
            return text
        }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(text.utf8.count)
        for byte in text.utf8 {
            if HTMLDecoder.isCollapsibleWhitespaceByte(byte) {
                if !prevSpace {
                    bytes.append(0x20)
                    prevSpace = true
                }
            } else {
                bytes.append(byte)
                prevSpace = false
            }
        }
        // Valid UTF-8 by construction: `text`'s own bytes plus ASCII spaces.
        // swiftlint:disable:next optional_data_string_conversion
        return String(decoding: bytes, as: UTF8.self)
    }

    /// Outside ASCII a space can share a character with a following combining
    /// mark (`" \u{301}"`) or a preceding prepend scalar, and that character is
    /// not whitespace, so classify by character.
    private static func collapseByCharacter(_ text: String, _ prevSpace: inout Bool) -> String {
        var collapsed = ""
        for char in text {
            if HTMLDecoder.isCollapsibleWhitespace(char) {
                if !prevSpace {
                    collapsed.append(" ")
                    prevSpace = true
                }
            } else {
                collapsed.append(char)
                prevSpace = false
            }
        }
        return collapsed
    }

    /// Joins consecutive runs sharing one inline state, each result carrying
    /// that state's attributes. Empty runs (text removed by collapsing) are
    /// skipped, so they never split two runs of the same state.
    private static func styledRuns(
        _ runs: [HTMLDecoder.Run]
    ) -> [(text: String, attributes: AttributeContainer)] {
        let runs = runs.filter { !$0.text.isEmpty }
        var styled: [(text: String, attributes: AttributeContainer)] = []
        var index = 0
        while index < runs.count {
            let state = runs[index].state
            var text = ""
            while index < runs.count, runs[index].state == state {
                text += runs[index].text
                index += 1
            }
            var attributes = AttributeContainer()
            if state.bold {
                attributes.bold = true
            }
            if state.italic {
                attributes.italic = true
            }
            if state.underline {
                attributes.underline = true
            }
            if state.strikethrough {
                attributes.strikethrough = true
            }
            if let color = state.color {
                attributes.textColor = color
            }
            styled.append((text, attributes))
        }
        return styled
    }
}
