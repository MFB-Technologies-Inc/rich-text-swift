// EditorEngine.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
import RichTextCore

/// The concept-level editing seam: semantic text, selection, typing attributes,
/// state to read, commands to apply. Deliberately says nothing about
/// `UITextView` — dev-plan §4 Layer 2 — so the future `NSTextView` engine
/// implements this same protocol and the whole UI layer above it carries over
/// untouched.
///
/// Main-actor bound because every implementation drives a text view, but it
/// imports no UI framework, so it compiles and is testable on any platform.
@MainActor
public protocol EditorEngine: AnyObject {
    /// The semantic document: block markers + inline attributes, no rendering
    /// attributes. This is the currency the serializer and the UI binding speak.
    var text: AttributedString { get set }

    /// The current selection, in UTF-16 offsets (`NSRange`-compatible).
    var selection: TextSelection { get set }

    /// Formatting that will apply to the next typed characters. Implementations
    /// re-derive this whenever `text` or `selection` changes.
    var typingAttributes: TypingAttributes { get }

    /// The formatting of the current selection, for driving toolbar state.
    var formatState: FormatState { get }

    /// Applies a formatting intent.
    func apply(_ command: FormatCommand)

    /// Applies the Return-key policy at the current selection (M4 decision D5):
    /// a list item continues the list, an empty list item leaves it, a
    /// heading's Return starts a paragraph. Platform adapters call this when
    /// they intercept the keystroke instead of letting the view insert a plain
    /// newline, which would silently drop the block's role.
    func insertNewline()

    /// Re-derives `typingAttributes` for the current `selection` after the
    /// selection changed but the text did not (arrow keys, tap-to-place).
    /// Cheap: implementations re-derive from the document already held in
    /// memory, with no storage conversion, so this is safe to call on every
    /// selection change. A pending block style (D13) is only kept correct if
    /// this is called on *every* one of them.
    func synchronizeSelection()

    /// Re-reads `text` after it changed by some means other than `apply(_:)`
    /// or the `text` setter — the user typed or pasted directly into the
    /// underlying platform view — and re-derives `typingAttributes` against
    /// the result. Implementations must pull the authoritative document back
    /// out of their underlying storage here, since it was mutated behind
    /// this engine's back.
    func synchronizeFromTextView()
}
