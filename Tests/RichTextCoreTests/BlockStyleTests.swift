// BlockStyleTests.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
@testable import RichTextCore
import Testing

struct BlockStyleTests {
    @Test func casesAreDistinct() {
        #expect(BlockStyle.paragraph != BlockStyle.heading(1))
        #expect(BlockStyle.heading(1) != BlockStyle.heading(2))
        #expect(BlockStyle.listItem(.ordered, depth: 0) != BlockStyle.listItem(.unordered, depth: 0))
        #expect(BlockStyle.listItem(.ordered, depth: 0) != BlockStyle.listItem(.ordered, depth: 1))
    }

    @Test func equalCasesMatch() {
        #expect(BlockStyle.heading(3) == BlockStyle.heading(3))
        #expect(BlockStyle.listItem(.unordered, depth: 2) == BlockStyle.listItem(.unordered, depth: 2))
    }

    @Test func codableRoundTrip() throws {
        let values: [BlockStyle] = [.paragraph, .heading(2), .listItem(.ordered, depth: 1)]
        for v in values {
            let data = try JSONEncoder().encode(v)
            let decoded = try JSONDecoder().decode(BlockStyle.self, from: data)
            #expect(decoded == v)
        }
    }

    @Test func listKindRawValues() {
        #expect(ListKind.unordered.rawValue == "unordered")
        #expect(ListKind.ordered.rawValue == "ordered")
    }
}
