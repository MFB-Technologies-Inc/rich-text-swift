// RichTextEditorModel.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
import Observation
import RichTextCore
import RichTextEngine

/// The ViewModel half of the MVVM split: every formatting action in the UI flows through here, never
/// by poking the text view directly. The declarative toolbar reads
/// `formatState` and calls `apply(_:)`, which is exactly the seam that makes a
/// public bring-your-own-toolbar API an additive change later.
///
/// Deliberately **internal** in v1, and deliberately UIKit-free: it speaks only
/// to the `EditorEngine` protocol, so its behavior is covered in the fast macOS
/// test loop even though the engine it drives at runtime is a `UITextView`.
@MainActor
@Observable
final class RichTextEditorModel {
    /// The current selection's formatting, republished after anything that
    /// could change it. Drives toolbar active/inactive state.
    private(set) var formatState = FormatState()

    /// Whether editing is allowed. Read by the toolbar to disable its
    /// controls, and mirrored onto the text view by the representable.
    ///
    /// It lives here rather than in the SwiftUI environment because the
    /// toolbar modifier sits *above* `RichTextEditor` and injects its model
    /// downward — there is no reverse channel for the editor to hand settings
    /// up to the bar. The model is the one piece of state both halves already
    /// share.
    private(set) var isEditable = true

    private var engine: (any EditorEngine)?

    /// Coalesces `scheduleRefresh()`: set the instant a hop is pending, so N
    /// calls within one main-actor turn (e.g. several caret moves) schedule a
    /// single `Task`, not N of them. Cleared *before* `refresh()` runs inside
    /// the task, so a refresh that itself provokes another `scheduleRefresh()`
    /// call (e.g. a delegate callback reentered from `refresh()`) still
    /// schedules its own follow-up hop rather than being silently dropped.
    private var refreshScheduled = false

    /// Fired at the end of a UI-originated mutation (`apply(_:)`,
    /// `insertNewline()`) so the coordinator can publish the resulting
    /// document to the consumer's `Binding` (without it, commands never
    /// called `textViewDidChange`, so a command applied through the toolbar
    /// silently never reached the binding). Deliberately NOT invoked from
    /// `setText(_:)`, which is itself the binding's write *into* the engine —
    /// firing here too would echo the write straight back out.
    var onDocumentChange: (() -> Void)?

    init() {}

    /// The semantic document. Empty until an engine is attached.
    var text: AttributedString {
        engine?.text ?? AttributedString()
    }

    /// Called by the representable once the platform view — and therefore the
    /// engine — exists.
    func attach(_ engine: any EditorEngine) {
        self.engine = engine
        // Reached from `makeUIView`/`setModel(_:)`, both inside the view-update
        // phase — see `scheduleRefresh()`.
        scheduleRefresh()
    }

    /// Applied by the representable from `RichTextEditor(text:isEditable:)`.
    /// A no-op when unchanged, so it is safe to call on every update pass —
    /// SwiftUI forbids mutating observed state during view updates, and this
    /// is reached from `updateUIView`.
    func setEditable(_ editable: Bool) {
        guard editable != isEditable else {
            return
        }
        isEditable = editable
    }

    func apply(_ command: FormatCommand) {
        // A read-only editor takes no commands, whatever route they arrive by.
        guard isEditable else {
            return
        }
        engine?.apply(command)
        refresh()
        onDocumentChange?()
    }

    func insertNewline() {
        guard isEditable else {
            return
        }
        engine?.insertNewline()
        refresh()
        onDocumentChange?()
    }

    func setText(_ text: AttributedString) {
        engine?.text = text
        // Reached from `updateUIView` -> `pushIfNeeded(_:)` — see
        // `scheduleRefresh()`.
        scheduleRefresh()
    }

    func synchronizeSelection() {
        engine?.synchronizeSelection()
        // Deferred, not synchronous: this can be reached from inside the
        // view-update phase (see `scheduleRefresh()`'s doc comment) — a
        // consumer's `setText(_:)` push can move the caret far enough that
        // `UIKitEditorEngine.render(restoring:)` clamps `selectedRange`,
        // which fires `UITextViewDelegate.textViewDidChangeSelection`
        // synchronously, which calls here.
        scheduleRefresh()
    }

    func synchronizeFromTextView() {
        engine?.synchronizeFromTextView()
        refresh()
    }

    /// Re-reads `formatState` from the engine. Every mutating entry point
    /// above except `synchronizeSelection()` (which defers through
    /// `scheduleRefresh()` instead, see there) calls this itself directly, so
    /// production code otherwise never needs to call it directly. Not
    /// `private`, because a test needs to force a resync after mutating a
    /// fake engine's state behind the model's back (see
    /// `RichTextEditorModelTests.refreshPicksUpStateChangedBehindTheModelsBack`).
    func refresh() {
        formatState = engine?.formatState ?? FormatState()
    }

    /// Republishes `formatState` on a **later** main-actor turn, coalescing
    /// any number of calls made before that turn lands into a single
    /// `refresh()`.
    ///
    /// SwiftUI forbids mutating observed state during its view-update phase.
    /// The representable reaches this model from there directly —
    /// `updateUIView` calls `setModel(_:)` (which attaches) and
    /// `pushIfNeeded(_:)` (which calls `setText(_:)`) — but also *indirectly*,
    /// through a synchronous delegate callback reentered from inside that
    /// same call stack: `setText(_:)` -> `UIKitEditorEngine.text`'s setter ->
    /// `render(restoring:)` can clamp `textView.selectedRange`, which fires
    /// `UITextViewDelegate.textViewDidChangeSelection` synchronously, which
    /// calls `synchronizeSelection()` before `setText(_:)` has even returned.
    /// So "reached from the update phase" is not limited to the
    /// representable's own two call sites; any path that can be reentered
    /// from inside one of them needs the same deferral. Before the toolbar
    /// existed this was harmless because nothing observed `formatState`; the
    /// toolbar observes it, which turns an undeferred call into the
    /// "Modifying state during view update" pattern — a diagnostic at best,
    /// an update loop at worst.
    ///
    /// User-driven mutations (`apply(_:)`, `insertNewline()`) deliberately
    /// keep publishing synchronously: they do not run in the update phase, and
    /// a toolbar must see the effect of its own tap immediately.
    func scheduleRefresh() {
        guard !refreshScheduled else {
            return
        }
        refreshScheduled = true
        Task { @MainActor [weak self] in
            self?.refreshScheduled = false
            self?.refresh()
        }
    }
}
