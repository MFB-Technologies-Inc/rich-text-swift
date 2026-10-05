// ListMarkers.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
import RichTextCore

/// The visible marker for each list block — **computed, never stored**.
/// Putting marker text in the document would corrupt the
/// model, the selection offsets, and the HTML, so the layout pass draws what
/// this returns and the document stays clean.
enum ListMarkers {
    /// Bullet glyph for an unordered item at `depth`, cycling every three levels.
    static func bullet(forDepth depth: Int) -> String {
        let glyphs = ["•", "◦", "▪"]
        return glyphs[max(0, depth) % glyphs.count]
    }

    /// One entry per block: the marker to draw, or `nil` for a non-list block.
    ///
    /// Ordinals count within a run of consecutive list items of the same kind
    /// at the same depth. Nesting does not interrupt the parent's sequence, but
    /// re-entering a nested level starts it over; any non-list block (including
    /// an empty one, which reports `.paragraph`) ends every run.
    static func markers(for blocks: [DocumentBlock]) -> [String?] {
        var counters: [Int: Int] = [:]
        var kinds: [Int: ListKind] = [:]
        var result: [String?] = []

        for block in blocks {
            guard case let .listItem(kind, depth) = block.style else {
                counters.removeAll()
                kinds.removeAll()
                result.append(nil)
                continue
            }
            let level = max(0, depth)
            // A shallower item ends any deeper sequence beneath it. Mutating
            // `counters` while iterating a snapshot of `counters.keys` is
            // safe and deterministic here: `Dictionary.keys` is a value-type
            // view taken at the start of the loop, so removals below never
            // change the set of keys this `for` is iterating over.
            for deeper in counters.keys where deeper > level {
                counters[deeper] = nil
                kinds[deeper] = nil
            }
            if kinds[level] != kind {
                counters[level] = 0
            }
            let ordinal = (counters[level] ?? 0) + 1
            counters[level] = ordinal
            kinds[level] = kind
            result.append(kind == .ordered ? "\(ordinal)." : bullet(forDepth: level))
        }
        return result
    }

    /// Which line fragments — by index into `lineStarts` — begin a block that
    /// has a marker, and what that marker is.
    ///
    /// TextKit does not always give one layout fragment per block: the
    /// document-final empty block is laid out as a second `NSTextLineFragment`
    /// inside the *same* fragment as the preceding paragraph, rather than
    /// getting a fragment of its own. So "one layout fragment = one block" —
    /// and therefore "one fragment = one marker" — does not hold, and a
    /// fragment must draw a marker on every line that begins a block, not
    /// just its first.
    ///
    /// A line gets a marker exactly when its start offset equals the start of
    /// a block that has one. A wrapped continuation line's start falls
    /// mid-block and never matches, so it never gets a marker.
    static func markers(forLineStartOffsets lineStarts: [Int], blocks: [DocumentBlock]) -> [Int: String] {
        var markerByBlockStart: [Int: String] = [:]
        for (block, marker) in zip(blocks, markers(for: blocks)) {
            guard let marker else { continue }
            markerByBlockStart[block.location] = marker
        }
        var result: [Int: String] = [:]
        for (lineIndex, start) in lineStarts.enumerated() {
            if let marker = markerByBlockStart[start] {
                result[lineIndex] = marker
            }
        }
        return result
    }
}
