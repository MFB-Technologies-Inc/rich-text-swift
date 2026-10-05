// FakeEditorEngine.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
import RichTextCore
import RichTextEngine

/// A UIKit-free `EditorEngine` for view-model tests: it records what the model
/// asked of it, so the model's own behavior can be tested without a text view.
@MainActor
final class FakeEditorEngine: EditorEngine {
    var text = AttributedString()
    var selection = TextSelection.caret(at: 0)
    var typingAttributes = TypingAttributes()
    var formatState = FormatState()

    private(set) var appliedCommands: [FormatCommand] = []
    private(set) var newlineCount = 0
    private(set) var selectionSyncCount = 0
    private(set) var textViewSyncCount = 0

    func apply(_ command: FormatCommand) {
        appliedCommands.append(command)
        formatState.bold = .on
    }

    func insertNewline() {
        newlineCount += 1
        text += AttributedString("\n")
    }

    func synchronizeSelection() {
        selectionSyncCount += 1
        // Distinct, discriminable mutation so a test can prove the model
        // actually republished this hook's result rather than merely calling
        // through to a counter.
        formatState.italic = .on
    }

    func synchronizeFromTextView() {
        textViewSyncCount += 1
        formatState.strikethrough = .on
    }
}
