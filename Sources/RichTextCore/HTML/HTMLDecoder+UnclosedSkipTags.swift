// HTMLDecoder+UnclosedSkipTags.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation

extension HTMLDecoder {
    /// Indices of tag tokens the decoder leaves out:
    /// - skip-element start tags (`<script>`, `<svg>`, `<head>`, …) that no end
    ///   tag closes. A skip region only ends at its element's own end tag, so
    ///   an unclosed one would swallow the rest of the document (GitHub issue
    ///   #52). Dropping the start tag decodes its content as ordinary content,
    ///   which also keeps the body when `</head>` is left out.
    /// - tags inside a raw-text element (`HTMLTagClasses.rawText`). They are
    ///   text in a browser, so they must neither pair with a skip tag outside
    ///   the element nor deepen the builder's count of nested skip elements.
    ///
    /// A raw-text element ends at the first end tag of its name, as in a
    /// browser. Other skip elements pair each end tag with the nearest
    /// unmatched start tag of the same name, matching how the builder
    /// depth-counts them, so a start tag left unpaired is exactly one whose
    /// region would never close.
    static func ignoredTags(in tokens: [HTMLToken]) -> Set<Int> {
        let rawTextEnds = rawTextEnds(in: tokens)
        var ignored = Set<Int>()
        var open: [String: [Int]] = [:]
        var index = 0
        while index < tokens.count {
            switch tokens[index] {
            case let .startTag(name, _, selfClosing):
                guard HTMLTagClasses.skipContent.contains(name), !selfClosing,
                      !HTMLTagClasses.void.contains(name) else { break }
                guard HTMLTagClasses.rawText.contains(name) else {
                    open[name, default: []].append(index)
                    break
                }
                guard let end = rawTextEnds[index] else {
                    ignored.insert(index)
                    break
                }
                for inner in index + 1 ..< end where !tokens[inner].isText {
                    ignored.insert(inner)
                }
                index = end
            case let .endTag(name):
                _ = open[name]?.popLast()
            case .text:
                break
            }
            index += 1
        }
        ignored.formUnion(open.values.joined())
        return ignored
    }

    /// For each raw-text start tag, the index of the first end tag of the same
    /// name after it, if any. One backward pass, so finding every end is linear
    /// however many raw-text elements are left unclosed.
    private static func rawTextEnds(in tokens: [HTMLToken]) -> [Int: Int] {
        var ends: [Int: Int] = [:]
        var nextEnd: [String: Int] = [:]
        for index in tokens.indices.reversed() {
            switch tokens[index] {
            case let .endTag(name) where HTMLTagClasses.rawText.contains(name):
                nextEnd[name] = index
            case let .startTag(name, _, false) where HTMLTagClasses.rawText.contains(name):
                ends[index] = nextEnd[name]
            default:
                break
            }
        }
        return ends
    }
}

extension HTMLToken {
    fileprivate var isText: Bool {
        if case .text = self {
            return true
        }
        return false
    }
}
