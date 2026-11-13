// MarkdownTestSupport.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
@testable import RichTextCore

/// Builders for blocks with mixed inline formatting, alongside `Sem`.
enum MD {
    enum Mark: Hashable {
        case bold, italic, strikethrough, underline
    }

    static func run(_ text: String, _ marks: Mark...) -> AttributedString {
        run(text, marks: Set(marks))
    }

    static func run(_ text: String, marks: Set<Mark>) -> AttributedString {
        var a = AttributedString(text)
        for mark in marks {
            switch mark {
            case .bold: a.bold = true
            case .italic: a.italic = true
            case .strikethrough: a.strikethrough = true
            case .underline: a.underline = true
            }
        }
        return a
    }

    /// One block made of `runs`, all carrying `style`.
    static func block(_ style: BlockStyle = .paragraph, _ runs: AttributedString...) -> AttributedString {
        var a = runs.reduce(AttributedString(), +)
        a.blockStyle = style
        return a
    }
}

extension AttributedString {
    /// A compact dump for failure messages: each run's text, marks and role.
    var markdownTestDescription: String {
        runs.map { run in
            var marks = ""
            if run.bold == true {
                marks += "b"
            }
            if run.italic == true {
                marks += "i"
            }
            if run.strikethrough == true {
                marks += "s"
            }
            let role = run.blockStyle.map { "\($0)" } ?? "-"
            return "\(String(self[run.range].characters).debugDescription)[\(marks)]{\(role)}"
        }.joined(separator: " ")
    }
}

/// A deterministic generator, so a failing generated document reproduces.
struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next(_ range: ClosedRange<Int>) -> Int {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return range.lowerBound + Int(z % UInt64(range.count))
    }
}
