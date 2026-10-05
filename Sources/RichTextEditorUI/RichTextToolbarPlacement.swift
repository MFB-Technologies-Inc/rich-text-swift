// RichTextToolbarPlacement.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation

/// Where `richTextToolbar(_:placement:)` puts the bar relative to the editor.
public enum RichTextToolbarPlacement: Hashable, Sendable {
    /// Above the editor. Always visible, and never competes with the keyboard.
    case top

    /// Below the editor. SwiftUI's keyboard safe area lifts it above the
    /// keyboard while editing, so it behaves much like an accessory view
    /// without any UIKit hosting (M5 decision D2). The default.
    case bottom
}
