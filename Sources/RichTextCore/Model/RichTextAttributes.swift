// RichTextAttributes.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation

/// Namespace for the custom `AttributedString` attributes that make up the
/// core document vocabulary. `CodableAttributedStringKey` (not plain
/// `AttributedStringKey`) so the runs can be archived later if needed.
///
/// The `blockStyle` marker is invisible/paragraph-level and is the source of
/// truth for block role. The inline flags map 1:1 to the
/// simple-HTML inline elements the serializer emits.
public enum RichTextAttributes {
    public enum BlockStyleKey: CodableAttributedStringKey {
        public typealias Value = BlockStyle
        public static let name = "com.mfbtech.rich-text-swift.blockStyle"
        public static let runBoundaries: AttributedString.AttributeRunBoundaries? = .paragraph
    }

    public enum BoldKey: CodableAttributedStringKey {
        public typealias Value = Bool
        public static let name = "com.mfbtech.rich-text-swift.bold"
    }

    public enum ItalicKey: CodableAttributedStringKey {
        public typealias Value = Bool
        public static let name = "com.mfbtech.rich-text-swift.italic"
    }

    public enum UnderlineKey: CodableAttributedStringKey {
        public typealias Value = Bool
        public static let name = "com.mfbtech.rich-text-swift.underline"
    }

    public enum StrikethroughKey: CodableAttributedStringKey {
        public typealias Value = Bool
        public static let name = "com.mfbtech.rich-text-swift.strikethrough"
    }

    public enum TextColorKey: CodableAttributedStringKey {
        public typealias Value = RichTextColor
        public static let name = "com.mfbtech.rich-text-swift.textColor"
    }

    /// Attribute scope bundling all core keys. The property names here are the
    /// dynamic-member names used on `AttributedString` / its run views.
    public struct Scope: AttributeScope {
        public let blockStyle: BlockStyleKey
        public let bold: BoldKey
        public let italic: ItalicKey
        public let underline: UnderlineKey
        public let strikethrough: StrikethroughKey
        public let textColor: TextColorKey
    }
}

extension AttributeScopes {
    /// Access point so `AttributeScopes` knows about the core scope.
    public var richText: RichTextAttributes.Scope.Type {
        RichTextAttributes.Scope.self
    }
}

extension AttributeDynamicLookup {
    /// Enables `attrStr.blockStyle`, `attrStr[range].bold`, etc.
    public subscript<T: AttributedStringKey>(
        dynamicMember _: KeyPath<RichTextAttributes.Scope, T>
    ) -> T {
        self[T.self]
    }
}
