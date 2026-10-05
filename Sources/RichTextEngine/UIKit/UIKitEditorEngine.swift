// UIKitEditorEngine.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

#if canImport(UIKit)
    import RichTextCore
    import UIKit

    private final class EditorNotificationTokens {
        var storageEdit: NSObjectProtocol?
        var undoClose: NSObjectProtocol?

        deinit {
            if let storageEdit {
                NotificationCenter.default.removeObserver(storageEdit)
            }
            if let undoClose {
                NotificationCenter.default.removeObserver(undoClose)
            }
        }
    }

    /// `EditorEngine` bound to a `UITextView` (TextKit 2 by default on iOS 17).
    ///
    /// Thin by construction (M3 decision D1): it owns the semantic document, hands
    /// every decision to `EngineCore`, and only translates — semantic text into
    /// `textStorage` via `UIKitRendering`, `NSRange` selections into
    /// `TextSelection` (both are UTF-16, so this is a straight copy), and
    /// `RenderedStyle` into `typingAttributes`.
    @MainActor
    public final class UIKitEditorEngine: EditorEngine {
        let textView: UITextView
        /// Read "as if injected" — v1 only ever passes `.default` (Decision #9).
        private let theme: Theme
        var semanticText: AttributedString
        public internal(set) var typingAttributes: TypingAttributes
        /// The selection `typingAttributes` was last derived against, so
        /// `refreshTypingAttributes()` can tell `EngineCore` whether the caret is
        /// still in the same (possibly still-empty) block or has moved to a
        /// different one — the only thing that legitimately lets a pending block
        /// style (D13) survive a selection change.
        var lastAttributesSelection: TextSelection
        /// Guards against re-entering the engine from the text view's own
        /// delegate callbacks while `render(restoring:)` is in the middle of
        /// updating storage (either in place or by reassigning it wholesale) and
        /// `selectedRange`. Per the wiring
        /// contract documented on `synchronizeSelection()` /
        /// `synchronizeFromTextView()` below, a real `UITextViewDelegate` calls
        /// `synchronizeSelection()` from `textViewDidChangeSelection` — and
        /// `render` updates storage then assigns `selectedRange`, each of which
        /// moves the caret and so re-enters that delegate hook *during* the
        /// render, against a half-updated view (text already swapped in, caret
        /// not yet where the render intends it). Without this guard that
        /// re-entrant call re-derives typing attributes from the wrong selection
        /// and both `typingAttributes` and `lastAttributesSelection` end up
        /// clobbered, which the render's own final `pushTypingAttributes()` then
        /// faithfully mirrors into the view. Set/cleared with `defer` so it
        /// cannot leak true on an early return.
        private var isRendering = false
        /// UIKit may still be inside the edit's undo group when it calls the
        /// delegate. Clearing that group early would unbalance UIKit's close.
        private let notificationTokens = EditorNotificationTokens()
        private var pendingEditedRange: NSRange?
        /// The state right after each recent caret command (`recordUndo(restoring:for:)`).
        var caretCommandStates: [UndoSnapshot] = []
        /// Draws list bullets/numbers in the indent gutter. Markers are computed
        /// from the semantic blocks and drawn at layout time — never stored in the
        /// document (M4 decision D7).
        ///
        /// Not `private`: `@testable import` needs to reach `marker(atUTF16Offset:)`
        /// directly to prove markers stay correct after an out-of-band edit (Fix 1)
        /// — the engine itself has no other window onto the controller's state.
        let listMarkers = ListMarkerLayoutController()

        /// The only initializer product code can reach: `RichTextEngine` is not a
        /// product and isn't re-exported, so this — not access control alone —
        /// is what keeps the `Theme` injection point unreachable from outside the
        /// package until it's deliberately opened up (Backlog: Theming B).
        public convenience init(textView: UITextView) {
            self.init(textView: textView, theme: .default)
        }

        init(textView: UITextView, theme: Theme) {
            self.textView = textView
            self.theme = theme
            let prefilled = UIKitRendering
                .semanticAttributedString(from: textView.attributedText ?? NSAttributedString())
            let prefilledSelection = TextSelection(
                location: textView.selectedRange.location,
                length: textView.selectedRange.length
            )
            // A pre-populated view can hold CRLF or explicit black; the render
            // below rewrites storage from the normalized document, so the
            // caller's selection is mapped onto it first.
            let ingested = EngineCore.normalizedIngest(prefilled, selection: prefilledSelection)
            semanticText = ingested?.text ?? prefilled
            typingAttributes = TypingAttributes()
            let initialSelection = ingested?.selection ?? prefilledSelection
            lastAttributesSelection = initialSelection
            // A text view can be handed over pre-populated with `attributedText`
            // carrying whatever visual attributes it already had (e.g. a stray
            // 40pt prefill), while the model reads it back as plain semantic
            // paragraphs. Render once, up front, so the view matches the theme
            // it will be edited through from the first frame rather than only
            // after the first command. Typing attributes are derived once
            // against `semanticText` (no pending block style can exist yet —
            // `typingAttributes` above is still the default) and pushed exactly
            // once via `render`, restoring the selection the caller handed us.
            typingAttributes = EngineCore.typingAttributes(at: initialSelection, in: semanticText)
            // `textLayoutManager` is nil only if UIKit ever falls back to TextKit 1;
            // tolerate that by simply not drawing markers rather than crashing.
            if let layoutManager = textView.textLayoutManager {
                listMarkers.install(on: layoutManager)
            }
            // `initialSelection` was mapped onto `semanticText` above, so a
            // selected range survives the normalizing render.
            if render(restoring: initialSelection, selectionIndexesRendered: true) {
                clearUndoHistoryWhenSafe()
            }
            // `render` only rewrites the view; typing attributes are pushed once
            // the re-entrancy guard it holds has cleared (see `isRendering`), so
            // a suppressed callback during the render never leaves the view's
            // typing attributes stale.
            pushTypingAttributes()
            notificationTokens.storageEdit = NotificationCenter.default.addObserver(
                forName: NSTextStorage.didProcessEditingNotification,
                object: textView.textStorage,
                queue: nil
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, !self.isRendering else { return }
                    let storage = self.textView.textStorage
                    if storage.editedMask.contains(.editedCharacters) {
                        self.pendingEditedRange = storage.editedRange
                    }
                }
            }
        }

        // MARK: - EditorEngine

        public var text: AttributedString {
            get { semanticText }
            set {
                // The representable's update loop (M4) is: delegate ->
                // `synchronizeFromTextView()` -> view model -> `Binding` ->
                // `updateUIView` -> `engine.text = binding.wrappedValue`. That
                // fires on every keystroke and hands back the very document this
                // engine just produced. Without this guard every one of those
                // echoes would re-enter `render(restoring:)` needlessly — and, per
                // its two-path behavior, a false negative on the in-place-render
                // check there would force the whole-`attributedText` reassignment
                // path, which can destroy in-progress IME marked text. A genuine
                // change (the document actually differs) still falls through and clears any
                // pending block style, since it cannot be trusted to still
                // describe the same empty block in a document the caller just
                // replaced wholesale.
                // Normalize line endings and any explicit black `textColor`
                // before comparing/storing the incoming document: `text` is public
                // (`RichTextEditor(text:)`'s binding writes through here), so a
                // consumer can hand over a document built entirely outside the
                // command layer and decoder's own normalization. Black is the
                // absence of a color everywhere in the system (see
                // `EngineCore.normalizingDefaultColor`), so no document this
                // engine holds may carry one, however it arrived.
                //
                // The live selection indexes the current `semanticText`, which
                // is already normalized, so it is kept as is (clamped by
                // `render`) rather than mapped through `newValue`'s CRLFs.
                let restoredSelection = selection
                let normalizedValue = EngineCore.normalizedIngest(newValue, selection: restoredSelection)?
                    .text ?? newValue
                guard normalizedValue != semanticText else {
                    return
                }
                semanticText = normalizedValue
                caretCommandStates = []
                // The incoming document is authoritative. A pending block style
                // (D13) captured against the *old* document cannot be trusted to
                // still describe the same empty block here — this is exactly
                // the caller-mutated-the-document case
                // `EngineCore.typingAttributes(movingTo:...)` warns about — so
                // derive fresh attributes before `render(restoring:)` updates
                // list markers using their pending block style.
                typingAttributes = EngineCore.typingAttributes(at: restoredSelection, in: semanticText)
                lastAttributesSelection = restoredSelection
                // The consumer's replacement records no undo entry, so existing
                // entries now describe ranges in a document that is gone, and
                // replaying one can throw an uncatchable `NSRangeException`.
                if render(restoring: restoredSelection) {
                    clearUndoHistoryWhenSafe()
                }
                pushTypingAttributes()
            }
        }

        public var selection: TextSelection {
            get {
                let range = textView.selectedRange
                return TextSelection(location: range.location, length: range.length)
            }
            set {
                textView.selectedRange = NSRange(location: newValue.location, length: newValue.length)
                refreshTypingAttributes()
            }
        }

        public var formatState: FormatState {
            EngineCore.formatState(of: semanticText, selection: selection, typingAttributes: typingAttributes)
        }

        public func apply(_ command: FormatCommand) {
            let before = undoSnapshot()
            let result = EngineCore.apply(
                command,
                to: semanticText,
                selection: selection,
                typingAttributes: typingAttributes
            )
            recordUndo(restoring: before, for: result)
            semanticText = result.text
            typingAttributes = result.typingAttributes
            render(restoring: result.selection)
            // `render` clamps `result.selection` to the new storage length, so
            // the bookkeeping must reflect the selection the view actually ends
            // up with (read back via the `selection` getter) rather than the
            // pre-clamp value `EngineCore` returned — otherwise the two disagree
            // until the next `refreshTypingAttributes()`.
            lastAttributesSelection = selection
            pushTypingAttributes()
        }

        public func insertNewline() {
            registerUndo(restoring: undoSnapshot())
            let result = EngineCore.insertNewline(
                in: semanticText,
                selection: selection,
                typingAttributes: typingAttributes
            )
            rememberPendingBlockStyleState(of: result)
            semanticText = result.text
            typingAttributes = result.typingAttributes
            render(restoring: result.selection)
            lastAttributesSelection = selection
            pushTypingAttributes()
        }

        // MARK: - Text view integration (driven by M4's delegate)

        //
        // Wiring contract the next milestone's `UITextViewDelegate` must follow —
        // both hooks are required, and neither substitutes for the other:
        //
        // - `textViewDidChangeSelection` -> `synchronizeSelection()`. The caret
        //   can move without any text changing (arrow keys, tap-to-place), and a
        //   pending block style (D13) is only kept correct if typing attributes
        //   are re-derived on *every* such move. `synchronizeSelection()` is
        //   cheap enough to call on every one of them because it never touches
        //   `NSAttributedString` — it only re-derives typing attributes from the
        //   semantic document already held in memory.
        // - `textViewDidChange` -> `synchronizeFromTextView()`. Typing or
        //   pasting mutates `textStorage` directly, bypassing this engine's
        //   `text` setter, so the semantic document itself must be pulled back
        //   out of storage — re-deriving typing attributes alone would read a
        //   stale document.
        //
        // Wiring only the cheap hook (`textViewDidChangeSelection`) misses real
        // edits; wiring only the expensive one, or calling
        // `synchronizeFromTextView()` on every selection change, pays a full
        // storage -> `AttributedString` conversion for a keystroke that changed
        // nothing (e.g. every arrow-key press). Both must be wired.

        /// Pulls the document back out of storage after the user typed or pasted.
        /// Semantic attributes survive editing because they ride in the storage
        /// attribute dictionaries and in `typingAttributes`. See the wiring
        /// contract above.
        public func synchronizeFromTextView() {
            // Suppress re-entrant calls made from inside `render(restoring:)`
            // (see `isRendering`) — that call is against a transient,
            // half-updated view and its own final `pushTypingAttributes()`
            // already leaves the view correct once the render completes.
            guard !isRendering else {
                return
            }
            let rawStorage = textView.attributedText ?? NSAttributedString()
            let editedStorage = editedStorageKeepingExistingLineBreaks(rawStorage, editedRange: pendingEditedRange)
            pendingEditedRange = nil
            let edited = UIKitRendering.semanticAttributedString(from: editedStorage)
            if let ingested = normalizedEdit(edited) {
                // UIKit put CR, explicit black or text with no block role into
                // storage on its own (drag and drop, the `.system` paste
                // fallback, typing over a selection). Storage
                // must hold the same characters as `semanticText` or every UTF-16
                // offset after a collapsed CRLF drifts, so render the normalized
                // document back. As in the `text` setter, the undo entries UIKit just
                // registered describe storage that no longer exists, and
                // replaying one can throw an uncatchable `NSRangeException`.
                // UIKit does not expose removal of only the latest action, so
                // this discards all prior undo history as well as this paste.
                semanticText = ingested.text
                if render(restoring: ingested.selection, selectionIndexesRendered: true) {
                    clearUndoHistoryWhenSafe()
                }
            } else {
                semanticText = edited
                if editedStorage !== rawStorage, render(restoring: selection, selectionIndexesRendered: true) {
                    clearUndoHistoryWhenSafe()
                }
            }
            // `lastAttributesSelection` was captured against the *pre-edit*
            // document, but `semanticText` above is now the *post-edit*
            // document — passing the old selection as `previouslyAt:` here is
            // exactly the caller-mutated-the-document precondition
            // `EngineCore.typingAttributes(movingTo:...)` warns about. Instead,
            // derive against the post-edit document using the *current*
            // selection for both `movingTo:` and `previouslyAt:`: a pending
            // block style then survives only if the caret's block is still the
            // same still-empty block in the document as it now stands, which is
            // the intended rule (D13) rather than a comparison against stale
            // pre-edit geometry.
            let currentSelection = selection
            typingAttributes = EngineCore.typingAttributes(
                movingTo: currentSelection,
                in: semanticText,
                previous: typingAttributes,
                previouslyAt: currentSelection
            )
            restoreCaretCommandTypingAttributes()
            lastAttributesSelection = currentSelection
            // This path never calls `render(restoring:)` — typing/pasting already
            // mutated `textStorage` directly — so nothing else here recomputes
            // the list markers or invalidates the fragments that cache them.
            // Without this, `listMarkers` keeps describing the document as of
            // the last *command*: every offset it looks up drifts against the
            // post-edit document until some unrelated event (rotation, scrolling
            // the paragraph back into view, ...) rebuilds that fragment, at which
            // point a marker can vanish, or a wrong glyph/ordinal can appear.
            listMarkers.update(
                for: semanticText,
                theme: theme,
                selection: currentSelection,
                pendingBlockStyle: typingAttributes.blockStyle
            )
            invalidateMarkerLayout()
            pushTypingAttributes()
        }

        /// A newly inserted CR immediately before an existing LF is a separate
        /// line break. The storage notification identifies the inserted span;
        /// only a CR at its end can merge with a pre-existing LF.
        private func editedStorageKeepingExistingLineBreaks(
            _ storage: NSAttributedString,
            editedRange: NSRange?
        ) -> NSAttributedString {
            guard let editedRange, editedRange.location != NSNotFound,
                  editedRange.length > 0,
                  editedRange.location <= storage.length,
                  editedRange.length < storage.length - editedRange.location
            else { return storage }

            let crIndex = NSMaxRange(editedRange) - 1
            let boundary = storage.attributedSubstring(from: NSRange(location: crIndex, length: 2))
            guard boundary.string == "\r\n" else { return storage }

            let attributes = storage.attributes(at: crIndex, effectiveRange: nil)
            let separated = NSMutableAttributedString(attributedString: storage)
            separated.replaceCharacters(
                in: NSRange(location: crIndex, length: 1),
                with: NSAttributedString(string: "\n", attributes: attributes)
            )
            return separated
        }

        private func clearUndoHistoryWhenSafe() {
            guard let undoManager = textView.undoManager else { return }
            if undoManager.groupingLevel == 0 {
                if let undoClose = notificationTokens.undoClose {
                    NotificationCenter.default.removeObserver(undoClose)
                    notificationTokens.undoClose = nil
                }
                undoManager.removeAllActions()
                return
            }
            guard notificationTokens.undoClose == nil else { return }
            // Notification delivery is synchronous with UIKit closing the
            // group. There is no run-loop interval in which old undo history
            // remains available after the group has closed.
            notificationTokens.undoClose = NotificationCenter.default.addObserver(
                forName: .NSUndoManagerDidCloseUndoGroup,
                object: undoManager,
                queue: nil
            ) { [weak self, weak undoManager] _ in
                MainActor.assumeIsolated {
                    guard let self, let undoManager, undoManager.groupingLevel == 0 else { return }
                    self.clearUndoHistoryWhenSafe()
                }
            }
        }

        /// Re-derives typing attributes for the current selection from the
        /// semantic document already held in memory — no `NSAttributedString`
        /// conversion, so this is cheap enough to call on every caret move. See
        /// the wiring contract above for when to use this versus
        /// `synchronizeFromTextView()`.
        public func synchronizeSelection() {
            // Suppress re-entrant calls made from inside `render(restoring:)`
            // (see `isRendering`) for the same reason as `synchronizeFromTextView()`.
            guard !isRendering else {
                return
            }
            refreshTypingAttributes()
        }

        // MARK: - Translation

        /// Rewrites the text view's storage from the semantic document and restores
        /// the given selection (clamped to the new length) in one step.
        ///
        /// Two paths (M4 decision D6). When the characters are unchanged — true of
        /// *every* formatting command, which only moves attributes — this re-applies
        /// attributes in place inside `beginEditing()`/`endEditing()` instead of
        /// reassigning `attributedText` wholesale. The demonstrable benefit is IME
        /// composition: reassigning `attributedText` while text is being composed
        /// (marked text) destroys the composition, whereas an attribute-only edit
        /// leaves it intact. (Undo coalescing and scroll/predictive-bar state were
        /// also suspected to depend on this, but measured identical under both
        /// paths on this OS version — those claims were not reproducible, so they
        /// are not asserted here.) Only a genuine document change replaces the
        /// characters wholesale.
        @discardableResult
        func render(restoring selection: TextSelection, selectionIndexesRendered: Bool = false) -> Bool {
            // See `isRendering`: the mutations below move the caret and so
            // re-enter this type's delegate-driven hooks against a transiently
            // half-updated view unless those hooks are suppressed for the
            // duration. `defer` guarantees the guard clears even if a future
            // edit adds an early return.
            isRendering = true
            defer { isRendering = false }

            // `typingAttributes` here is already the value the caller wants live
            // after this render (every call site sets it before calling
            // `render`), and `selection` is the caret it's restoring to — exactly
            // the pair `effectiveBlocks` needs to know whether a pending block
            // style (D13) applies to the block the caret is about to sit in.
            listMarkers.update(
                for: semanticText,
                theme: theme,
                selection: selection,
                pendingBlockStyle: typingAttributes.blockStyle
            )
            let rendered = UIKitRendering.nsAttributedString(
                from: semanticText,
                theme: theme,
                selection: selection,
                pendingBlockStyle: typingAttributes.blockStyle
            )
            return TextViewStorageWriter.write(
                rendered,
                to: textView,
                restoring: selection,
                selectionIndexesRendered: selectionIndexesRendered
            )
        }

        /// Re-derives typing attributes from the document, delegating the
        /// pending-block-style-survival rule (D13) entirely to `EngineCore`: a
        /// pending style carries forward only while the caret stays within the
        /// same still-empty block it was set in, never across a move to a
        /// different (also empty) block.
        ///
        /// A pending block style can appear or disappear here with *no* text
        /// change at all — moving the caret onto or off an empty block — and
        /// this is the only path where that happens outside `render(restoring:)`,
        /// so it must also refresh the markers and invalidate layout itself, or a
        /// bullet can linger on (or fail to appear on) a line whose pending role
        /// just changed.
        private func refreshTypingAttributes() {
            let currentSelection = selection
            typingAttributes = EngineCore.typingAttributes(
                movingTo: currentSelection,
                in: semanticText,
                previous: typingAttributes,
                previouslyAt: lastAttributesSelection
            )
            lastAttributesSelection = currentSelection
            listMarkers.update(
                for: semanticText,
                theme: theme,
                selection: currentSelection,
                pendingBlockStyle: typingAttributes.blockStyle
            )
            invalidateMarkerLayout()
            pushTypingAttributes()
        }

        /// Mirrors typing attributes into the text view so the *next* typed
        /// characters carry both the rendering and the semantic attributes.
        func pushTypingAttributes() {
            // `formatState.blockStyle` is already the seam's answer (`nil` for a
            // selection spanning differing roles) — hand it straight to the
            // overload that accepts an optional rather than substituting
            // `.paragraph` here; `StyleResolver` is where that mixed-selection
            // decision belongs, not this adapter.
            let block = formatState.blockStyle
            let style = StyleResolver.resolve(block: block, typingAttributes: typingAttributes, theme: theme)
            let semantic = SemanticNSBridge.semanticAttributes(block: block, typingAttributes: typingAttributes)
            textView.typingAttributes = UIKitRendering.attributes(for: style, semantic: semantic)
        }

        /// Forces every cached layout fragment to be rebuilt against the markers
        /// `listMarkers` was just recomputed for. Needed only on the
        /// `synchronizeFromTextView()` path (Fix 1): `render(restoring:)`
        /// mutates `textStorage` itself, which TextKit already treats as
        /// invalidating; this path deliberately does not touch storage, so
        /// nothing else tells the layout manager its fragments are stale.
        private func invalidateMarkerLayout() {
            guard let layoutManager = textView.textLayoutManager,
                  let documentRange = layoutManager.textContentManager?.documentRange
            else {
                return
            }
            layoutManager.invalidateLayout(for: documentRange)
        }
    }
#endif
