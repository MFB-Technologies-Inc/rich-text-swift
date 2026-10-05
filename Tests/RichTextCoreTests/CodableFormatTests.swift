// CodableFormatTests.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
@testable import RichTextCore
import Testing

/// Pins the exact JSON of the Codable format (GitHub issue #82). Apps persist
/// this output, so any change here breaks their saved documents: a failure in
/// this file means the format changed, and the fix is almost never to update
/// the expected string.
struct CodableFormatTests {
    struct Note: Codable, Equatable {
        @CodableConfiguration(from: \.richText) var body = AttributedString()
    }

    private static func json(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try #require(String(bytes: encoder.encode(value), encoding: .utf8))
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    static let blockStyles: [(BlockStyle, String)] = [
        (.paragraph, #"{"type":"paragraph"}"#),
        (.heading(1), #"{"level":1,"type":"heading"}"#),
        (.heading(3), #"{"level":3,"type":"heading"}"#),
        (.listItem(.unordered, depth: 0), #"{"depth":0,"list":"unordered","type":"listItem"}"#),
        (.listItem(.ordered, depth: 2), #"{"depth":2,"list":"ordered","type":"listItem"}"#),
        (.blockquote, #"{"type":"blockquote"}"#),
    ]

    @Test(arguments: blockStyles.indices)
    func blockStyleEncodesToPinnedJSON(_ index: Int) throws {
        let (style, expected) = Self.blockStyles[index]
        #expect(try Self.json(style) == expected)
    }

    @Test(arguments: blockStyles.indices)
    func blockStyleDecodesFromPinnedJSON(_ index: Int) throws {
        let (style, json) = Self.blockStyles[index]
        #expect(try Self.decode(BlockStyle.self, json) == style)
    }

    /// A newer library version may add block roles this one doesn't know.
    /// Those blocks degrade to a paragraph so the rest of the document still
    /// opens, rather than the whole decode failing.
    @Test func unknownBlockTypeDecodesAsParagraph() throws {
        #expect(try Self.decode(BlockStyle.self, #"{"type":"codeBlock","language":"swift"}"#) == .paragraph)
    }

    /// Likewise for a list kind added later: it keeps its list membership and
    /// depth, shown as a bulleted item.
    @Test func unknownListKindDecodesAsUnorderedListItem() throws {
        let json = #"{"type":"listItem","list":"task","depth":1,"checked":true}"#
        #expect(try Self.decode(BlockStyle.self, json) == .listItem(.unordered, depth: 1))
    }

    @Test func documentWithAnUnknownBlockTypeStillDecodes() throws {
        let json = #"{"body":["Code",{"com.mfbtech.rich-text-swift.blockStyle":{"type":"codeBlock"}}]}"#
        var expected = AttributedString("Code")
        expected.blockStyle = .paragraph
        #expect(try Self.decode(Note.self, json).body == expected)
    }

    @Test func blockStyleMissingAFieldFailsToDecode() {
        #expect(throws: DecodingError.self) {
            try Self.decode(BlockStyle.self, #"{"type":"heading"}"#)
        }
        #expect(throws: DecodingError.self) {
            try Self.decode(BlockStyle.self, #"{"type":"listItem","list":"ordered"}"#)
        }
    }

    @Test func colorEncodesAsHexString() throws {
        #expect(try Self.json(RichTextColor(red: 255, green: 59, blue: 48)) == ##""#ff3b30""##)
    }

    @Test func colorDecodesFromHexString() throws {
        #expect(try Self.decode(RichTextColor.self, ##""#ff3b30""##) == RichTextColor(red: 255, green: 59, blue: 48))
    }

    @Test func malformedColorFailsToDecode() {
        #expect(throws: DecodingError.self) {
            try Self.decode(RichTextColor.self, #""red""#)
        }
        #expect(throws: DecodingError.self) {
            try Self.decode(RichTextColor.self, #"{"red":255,"green":0,"blue":0}"#)
        }
    }

    @Test func documentEncodesToPinnedJSON() throws {
        var title = AttributedString("Title\n")
        title.blockStyle = .heading(1)
        var item = AttributedString("Red")
        item.blockStyle = .listItem(.ordered, depth: 0)
        item.bold = true
        item.textColor = RichTextColor(red: 255, green: 0, blue: 0)

        let expected = #"{"body":["Title\n",{"com.mfbtech.rich-text-swift.blockStyle":{"level":1,"type":"heading"}},"#
            + #""Red",{"com.mfbtech.rich-text-swift.blockStyle":{"depth":0,"list":"ordered","type":"listItem"},"#
            + ##""com.mfbtech.rich-text-swift.bold":true,"com.mfbtech.rich-text-swift.textColor":"#ff0000"}]}"##
        #expect(try Self.json(Note(body: title + item)) == expected)
    }

    @Test func documentRoundTripsThroughCodableConfiguration() throws {
        var doc = AttributedString("Title\n")
        doc.blockStyle = .heading(2)
        var quote = AttributedString("Quoted")
        quote.blockStyle = .blockquote
        quote.italic = true
        quote.underline = true
        quote.strikethrough = true
        quote.textColor = RichTextColor(red: 0, green: 128, blue: 255)
        doc += quote

        let data = try JSONEncoder().encode(Note(body: doc))
        #expect(try JSONDecoder().decode(Note.self, from: data).body == doc)
    }
}
