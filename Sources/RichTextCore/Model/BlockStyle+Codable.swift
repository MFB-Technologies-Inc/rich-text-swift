// BlockStyle+Codable.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation

/// Hand-written so the saved format belongs to us, not to how the enum happens
/// to be declared (GitHub issue #82). Synthesized coding keys an unlabeled
/// associated value as `"_0"`, so renaming a case or labeling a value would
/// silently stop every saved document from decoding. The shapes are:
///
///     {"type":"paragraph"}
///     {"type":"heading","level":1}
///     {"type":"listItem","list":"ordered","depth":0}
///     {"type":"blockquote"}
///
/// Decoding is forward-compatible: a block `type` or list kind added by a
/// later version degrades (to `.paragraph`, or to an unordered item at the
/// same depth) instead of failing, so a document saved by a newer app still
/// opens in an older one. A known type with a missing field still throws.
///
/// `CodableFormatTests` pins this JSON; change it only on purpose.
extension BlockStyle {
    private enum CodingKeys: String, CodingKey {
        case type
        case level
        case list
        case depth
    }

    private enum Kind: String, Codable {
        case paragraph
        case heading
        case listItem
        case blockquote
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch Kind(rawValue: type) {
        case .paragraph, nil:
            self = .paragraph
        case .heading:
            self = try .heading(container.decode(Int.self, forKey: .level))
        case .listItem:
            let list = try container.decode(String.self, forKey: .list)
            self = try .listItem(
                ListKind(rawValue: list) ?? .unordered,
                depth: container.decode(Int.self, forKey: .depth)
            )
        case .blockquote:
            self = .blockquote
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .paragraph:
            try container.encode(Kind.paragraph, forKey: .type)
        case let .heading(level):
            try container.encode(Kind.heading, forKey: .type)
            try container.encode(level, forKey: .level)
        case let .listItem(kind, depth):
            try container.encode(Kind.listItem, forKey: .type)
            try container.encode(kind, forKey: .list)
            try container.encode(depth, forKey: .depth)
        case .blockquote:
            try container.encode(Kind.blockquote, forKey: .type)
        }
    }
}
