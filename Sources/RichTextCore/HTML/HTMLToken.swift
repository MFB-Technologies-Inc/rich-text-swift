// HTMLToken.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

enum HTMLToken: Equatable {
    case text(String)
    case startTag(name: String, attributes: [String: String], selfClosing: Bool)
    case endTag(name: String)
}
