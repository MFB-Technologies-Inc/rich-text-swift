// InMemoryEditorEngine.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
import RichTextCore
@testable import RichTextEngine

/// A UIKit-free `EditorEngine` backed by nothing but a stored AttributedString.
/// Exercises the seam exactly as `UIKitEditorEngine` does, minus the text view —
/// which is the point of the seam.
///
/// Mirrors the real engine's state machine: the `selection` setter re-derives
/// via `EngineCore.typingAttributes(movingTo:in:previous:previouslyAt:)`,
/// which lets a *pending* block style survive being re-collapsed onto
/// the exact same empty block, while still dropping it the moment the caret
/// moves to a different (even if also empty) block. `lastAttributesSelection`
/// is the bookkeeping that makes that comparison possible — it tracks the
/// selection `typingAttributes` was last derived against, exactly as
/// `UIKitEditorEngine.lastAttributesSelection` does. A wholesale `text`
/// assignment is the "the caller mutated the document out from under us"
/// case `typingAttributes(movingTo:...)` warns about, so — for a genuinely
/// different document — it clears any pending role and re-derives fresh via
/// `typingAttributes(at:in:)` instead, again matching the real engine's `text`
/// setter; an *equal* assignment early-returns and touches nothing, including
/// the pending role, exactly as `UIKitEditorEngine.text`'s idempotence guard
/// does (fix wave H) — see the `text` setter below. Note this *does* mean the
/// real engine re-derives on every incidental (non-equal) selection
/// assignment too (its `selection` setter always calls
/// `refreshTypingAttributes()`); the difference from this double is only in
/// *which* `EngineCore` function does the re-deriving, not whether it happens.
///
/// `simulateSelectionChange(_:)` and `simulateTextChange(_:)` below are
/// test-only affordances standing in for the text view mutating its own
/// selection/storage *behind this engine's back* — exactly what a real
/// `UITextView` does on every arrow key, tap-to-place, keystroke, or paste.
/// Production's equivalents are the `UITextViewDelegate` callbacks
/// (`textViewDidChangeSelection` / `textViewDidChange`), which is
/// why they exist as separate affordances rather than routing through
/// `selection`/`text`: those setters *are* this double's synchronous
/// equivalent of "the app called `EditorEngine.selection = ...`", which
/// already refreshes typing attributes and so can never exercise
/// `synchronizeSelection()`/`synchronizeFromTextView()` — the whole reason
/// those two hooks exist is to catch up after a mutation that did *not* go
/// through this engine.
@MainActor
final class InMemoryEditorEngine: EditorEngine {
    private var storage = AttributedString()
    private var currentSelection = TextSelection.caret(at: 0)
    private(set) var typingAttributes = TypingAttributes()
    /// The selection `typingAttributes` was last derived against — mirrors
    /// `UIKitEditorEngine.lastAttributesSelection`.
    private var lastAttributesSelection = TextSelection.caret(at: 0)

    var text: AttributedString {
        get { storage }
        set {
            // Mirrors `UIKitEditorEngine.text`'s idempotence guard (fix wave
            // H): an equal assignment — e.g. SwiftUI's `updateUIView` echoing
            // back the very document this engine just produced — is a no-op,
            // including for any pending block style. Only a genuinely
            // different document falls through: the incoming document is
            // then authoritative, and a pending block style captured against
            // the old document cannot be trusted to still describe the same
            // empty block here, so it derives fresh rather than carrying it
            // forward.
            guard newValue != storage else {
                return
            }
            storage = newValue
            typingAttributes = EngineCore.typingAttributes(at: currentSelection, in: storage)
            lastAttributesSelection = currentSelection
        }
    }

    var selection: TextSelection {
        get { currentSelection }
        set {
            let previous = lastAttributesSelection
            currentSelection = newValue
            typingAttributes = EngineCore.typingAttributes(
                movingTo: newValue,
                in: storage,
                previous: typingAttributes,
                previouslyAt: previous
            )
            lastAttributesSelection = newValue
        }
    }

    var formatState: FormatState {
        EngineCore.formatState(of: storage, selection: currentSelection, typingAttributes: typingAttributes)
    }

    func apply(_ command: FormatCommand) {
        let result = EngineCore.apply(
            command,
            to: storage,
            selection: currentSelection,
            typingAttributes: typingAttributes
        )
        storage = result.text
        currentSelection = result.selection
        typingAttributes = result.typingAttributes
        lastAttributesSelection = result.selection
    }

    func insertNewline() {
        let result = EngineCore.insertNewline(
            in: storage,
            selection: currentSelection,
            typingAttributes: typingAttributes
        )
        storage = result.text
        currentSelection = result.selection
        typingAttributes = result.typingAttributes
        lastAttributesSelection = result.selection
    }

    /// Mirrors `UIKitEditorEngine.synchronizeSelection()`: re-derives typing
    /// attributes for the current selection from the document already held
    /// in memory. There is no separate "storage" to read here — `storage`
    /// itself already is the semantic document — so this is exactly
    /// `refreshTypingAttributes` factored out, matching the real engine's
    /// split between the cheap (selection-only) and expensive (text-reread)
    /// hooks even though both are equally cheap for this double.
    func synchronizeSelection() {
        refreshTypingAttributes()
    }

    /// Mirrors `UIKitEditorEngine.synchronizeFromTextView()`: re-reads the
    /// document after an external mutation. This double has no independent
    /// backing store to pull from (`storage` already is the document,
    /// there's no `UITextView.attributedText` underneath it), so "re-reading"
    /// is a no-op on `storage` itself — what matters, and what this mirrors,
    /// is re-deriving `typingAttributes` against the *current* selection for
    /// both `movingTo:` and `previouslyAt:`, exactly as the real engine does
    /// once its post-edit document is back in hand.
    func synchronizeFromTextView() {
        typingAttributes = EngineCore.typingAttributes(
            movingTo: currentSelection,
            in: storage,
            previous: typingAttributes,
            previouslyAt: currentSelection
        )
        lastAttributesSelection = currentSelection
    }

    private func refreshTypingAttributes() {
        typingAttributes = EngineCore.typingAttributes(
            movingTo: currentSelection,
            in: storage,
            previous: typingAttributes,
            previouslyAt: lastAttributesSelection
        )
        lastAttributesSelection = currentSelection
    }

    // MARK: - Test-only text-view stand-ins

    /// Test-only affordance standing in for the text view moving its own
    /// caret behind this engine's back — arrow keys, tap-to-place. The
    /// production equivalent is `UITextViewDelegate.textViewDidChangeSelection`,
    /// wired to call `synchronizeSelection()`. Moves the selection only;
    /// deliberately does **not** refresh `typingAttributes` or
    /// `lastAttributesSelection` the way the `selection` setter above does,
    /// so a test can observe `typingAttributes` go stale and then confirm
    /// `synchronizeSelection()` — not this call — is what corrects it.
    func simulateSelectionChange(_ newSelection: TextSelection) {
        currentSelection = newSelection
    }

    /// Test-only affordance standing in for the text view mutating its own
    /// storage behind this engine's back — typing, paste. The production
    /// equivalent is `UITextViewDelegate.textViewDidChange`, wired to
    /// call `synchronizeFromTextView()`. Replaces the stored document only;
    /// deliberately does **not** refresh `typingAttributes` the way the
    /// `text` setter above does, so a test can observe `typingAttributes` go
    /// stale and then confirm `synchronizeFromTextView()` — not this call —
    /// is what corrects it.
    func simulateTextChange(_ newText: AttributedString) {
        storage = newText
    }
}
