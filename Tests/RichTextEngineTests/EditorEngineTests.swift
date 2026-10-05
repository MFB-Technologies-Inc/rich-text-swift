// EditorEngineTests.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
import RichTextCore
@testable import RichTextEngine
import Testing

@MainActor
struct EditorEngineTests {
    private func engine(_ text: AttributedString) -> InMemoryEditorEngine {
        let engine = InMemoryEditorEngine()
        engine.text = text
        return engine
    }

    @Test func applyingBoldFlipsFormatState() {
        let engine = engine(Sem.block("abcdef"))
        engine.selection = TextSelection(location: 0, length: 3)
        #expect(engine.formatState.bold == .off)
        engine.apply(.toggleBold)
        #expect(engine.formatState.bold == .on)
        engine.apply(.toggleBold)
        #expect(engine.formatState.bold == .off)
    }

    @Test func applyingHeadingFlipsBlockState() {
        let engine = engine(Sem.doc(Sem.block("Title"), Sem.block("Body")))
        engine.selection = .caret(at: 1)
        #expect(engine.formatState.blockStyle == .paragraph)
        engine.apply(.toggleHeading(2))
        #expect(engine.formatState.blockStyle == .heading(2))
        // The other block is untouched.
        engine.selection = .caret(at: 7)
        #expect(engine.formatState.blockStyle == .paragraph)
    }

    @Test func caretToggleThenBlockChangeKeepsInlineIntent() {
        let engine = engine(Sem.block("abc"))
        engine.selection = .caret(at: 3)
        engine.apply(.toggleItalic)
        #expect(engine.formatState.italic == .on)
        engine.apply(.toggleHeading(1))
        #expect(engine.formatState.blockStyle == .heading(1))
        #expect(engine.formatState.italic == .on)
    }

    @Test func movingTheSelectionRederivesTypingAttributes() {
        var doc = Sem.block("abcdef")
        doc[TextOffsets.range(TextSelection(location: 0, length: 3), in: doc)].bold = true
        let engine = engine(doc)
        engine.selection = .caret(at: 3)
        #expect(engine.typingAttributes.bold)
        engine.selection = .caret(at: 6)
        #expect(engine.typingAttributes.bold == false)
    }

    @Test func settingTextResetsTypingAttributesFromTheNewDocument() {
        let engine = engine(Sem.block("abc"))
        engine.selection = .caret(at: 1)
        engine.apply(.toggleBold)
        #expect(engine.typingAttributes.bold)
        engine.text = Sem.block("xyz")
        #expect(engine.typingAttributes.bold == false)
    }

    @Test func engineRoundTripsThroughTheSerializer() {
        let engine = engine(RichTextHTML.decode("<p>one</p><p>two</p>"))
        engine.selection = TextSelection(location: 0, length: 7)
        engine.apply(.toggleList(.ordered))
        engine.apply(.toggleBold)
        #expect(RichTextHTML.encode(engine.text) == "<ol><li><b>one</b></li><li><b>two</b></li></ol>")
    }

    // MARK: - Empty-block pending block style (M3 decision D13), through the seam

    /// Toggling a heading with the caret in an empty block cannot mark any
    /// character (there are none), so the pending role lives only in
    /// `TypingAttributes.blockStyle`. This must be visible through both
    /// `formatState` (for toolbar highlighting) and `typingAttributes` (for
    /// what the next typed character inherits), while the document itself
    /// stays untouched — there is nothing yet to attribute.
    @Test func togglingHeadingInAnEmptyBlockReportsPendingStyleThroughTheSeam() {
        let engine = engine(AttributedString())
        #expect(engine.formatState.blockStyle == .paragraph)
        engine.apply(.toggleHeading(1))
        #expect(engine.formatState.blockStyle == .heading(1))
        #expect(engine.typingAttributes.blockStyle == .heading(1))
        #expect(engine.text.characters.isEmpty)
    }

    /// The pending block style and an inline caret toggle are independent
    /// intents that must coexist: applying bold after the heading toggle
    /// (still on the same empty-block caret) must not clobber the pending
    /// heading, and both must show up in `formatState` together.
    @Test func inlineToggleAfterPendingHeadingKeepsBothIntents() {
        let engine = engine(AttributedString())
        engine.apply(.toggleHeading(1))
        engine.apply(.toggleBold)
        #expect(engine.formatState.blockStyle == .heading(1))
        #expect(engine.formatState.bold == .on)
        #expect(engine.typingAttributes.blockStyle == .heading(1))
        #expect(engine.typingAttributes.bold)
    }

    /// `InMemoryEditorEngine.selection`'s setter re-derives via
    /// `EngineCore.typingAttributes(movingTo:in:previous:previouslyAt:)`,
    /// mirroring `UIKitEditorEngine`: re-collapsing the selection onto the
    /// *exact same* still-empty block it was already in preserves a pending
    /// block style, because the block the caret was previously in and the
    /// block it's moving to are the same empty block.
    @Test func reassigningTheSameSelectionPreservesThePendingStyle() {
        let engine = engine(AttributedString())
        engine.apply(.toggleHeading(1))
        #expect(engine.formatState.blockStyle == .heading(1))
        engine.selection = engine.selection // same caret, re-assigned
        #expect(engine.formatState.blockStyle == .heading(1))
        #expect(engine.typingAttributes.blockStyle == .heading(1))
    }

    /// The leak this double now pins at the seam: a pending block style is
    /// per-empty-block intent, not global. Moving the caret from one empty
    /// block to a *different* empty block must drop it, even though both
    /// blocks are (still) empty.
    @Test func togglingHeadingThenMovingToADifferentEmptyBlockDropsThePendingStyle() {
        // "\n" splits into two empty blocks: one at offset 0, one at offset 1.
        let engine = engine(AttributedString("\n"))
        engine.apply(.toggleHeading(1))
        #expect(engine.formatState.blockStyle == .heading(1))
        engine.selection = .caret(at: 1) // a different empty block
        #expect(engine.formatState.blockStyle == .paragraph)
        #expect(engine.typingAttributes.blockStyle == nil)
    }

    /// Typing a character commits whatever block style was pending: the
    /// caller inserts the new character carrying the current typing
    /// attributes (including the pending `blockStyle`) via a wholesale
    /// `text` assignment, and the marker lands on the document itself rather
    /// than remaining bookkeeping-only.
    @Test func togglingHeadingOnABlankLineThenTypingLandsTheMarker() {
        let engine = engine(AttributedString())
        engine.apply(.toggleHeading(1))
        #expect(engine.typingAttributes.blockStyle == .heading(1))

        var typed = AttributedString("H")
        typed.blockStyle = engine.typingAttributes.blockStyle
        engine.text = typed
        engine.selection = .caret(at: 1)

        #expect(engine.text.runs.first?.blockStyle == .heading(1))
        #expect(engine.formatState.blockStyle == .heading(1))
    }

    /// A wholesale `text` assignment is the "caller mutated the document"
    /// case `EngineCore.typingAttributes(movingTo:...)` warns about: a
    /// pending role captured against the old document cannot be trusted to
    /// still describe the same empty block in the new one, so it is cleared
    /// rather than carried forward.
    /// A wholesale `text` assignment only clears a pending role when the
    /// incoming document is *genuinely different* from the one already held.
    /// `InMemoryEditorEngine.text`'s idempotence guard (mirroring
    /// `UIKitEditorEngine.text`, fix wave H) makes an *equal* assignment —
    /// e.g. SwiftUI's `updateUIView` echoing the identical document back — a
    /// complete no-op, so the pending role survives it; that's the better
    /// behavior, since clearing on an echo would drop the toolbar's H1
    /// highlight and make the next typed character land as paragraph text.
    /// Only a document that actually differs is the "caller mutated the
    /// document out from under us" case `EngineCore.typingAttributes(movingTo:...)`
    /// warns about, and that does clear it.
    @Test func assigningAnEqualDocumentPreservesThePendingRoleButADifferentDocumentClearsIt() {
        let engine = engine(AttributedString())
        engine.apply(.toggleHeading(1))
        #expect(engine.typingAttributes.blockStyle == .heading(1))

        // Equal assignment: a no-op, so the pending role survives.
        engine.text = AttributedString()
        #expect(engine.typingAttributes.blockStyle == .heading(1))
        #expect(engine.formatState.blockStyle == .heading(1))

        // Genuinely different document: the pending role cannot be trusted
        // to still describe the same empty block, so it is cleared.
        engine.text = AttributedString("x")
        #expect(engine.typingAttributes.blockStyle == nil)
        #expect(engine.formatState.blockStyle == .paragraph)
    }

    // MARK: - Protocol-level synchronization hooks (Fix 2)

    //
    // `synchronizeSelection()` and `synchronizeFromTextView()` are declared on
    // `EditorEngine` itself, not just the concrete UIKit adapter, so a caller
    // holding only the protocol type can drive them — exactly what these
    // tests do, going through `EditorEngine` rather than `InMemoryEditorEngine`
    // directly.

    /// The "external mutation" is delivered via `simulateTextChange`/
    /// `simulateSelectionChange` — the storage and selection change *without*
    /// going through the `text`/`selection` setters, so `typingAttributes` is
    /// left stale on purpose. Only `synchronizeFromTextView()` should bring it
    /// back into agreement with what `text` and `selection` now actually say;
    /// if its body were empty, the final assertions below would still see the
    /// pre-mutation (stale) value.
    @Test func synchronizeFromTextViewReReadsAnExternallyMutatedDocumentConsistently() {
        let concrete = InMemoryEditorEngine()
        let engine: EditorEngine = concrete
        engine.text = Sem.block("abc")
        engine.selection = .caret(at: 3)
        engine.apply(.toggleBold)
        #expect(engine.typingAttributes.bold)

        // The underlying document changes by some means other than `apply(_:)`
        // or the `text`/`selection` setters — the double's stand-in for "the
        // user typed/pasted directly into the text view". Only the first 3
        // characters are bold this time, and the caret moves to the (unbold)
        // end, so the correct post-sync answer disagrees with the stale one.
        var mutated = Sem.block("abcdef")
        mutated[TextOffsets.range(TextSelection(location: 0, length: 3), in: mutated)].bold = true
        concrete.simulateTextChange(mutated)
        concrete.simulateSelectionChange(.caret(at: 6))

        // Stale: neither simulate call touched `typingAttributes`, so it
        // still reflects the pre-mutation derivation.
        #expect(engine.typingAttributes.bold)

        engine.synchronizeFromTextView()

        #expect(engine.text == mutated)
        #expect(engine.typingAttributes.bold == false)
        #expect(engine.formatState.bold == .off)
    }

    /// The caret move is delivered via `simulateSelectionChange`, which
    /// (unlike the `selection` setter) leaves `typingAttributes` untouched —
    /// so only `synchronizeSelection()` re-deriving it can make the
    /// post-sync assertions pass; an empty hook body would leave the stale,
    /// pre-move value in place instead.
    @Test func synchronizeSelectionRederivesTypingAttributesForTheCurrentSelection() {
        var doc = Sem.block("abcdef")
        doc[TextOffsets.range(TextSelection(location: 0, length: 3), in: doc)].bold = true
        let concrete = InMemoryEditorEngine()
        let engine: EditorEngine = concrete
        engine.text = doc
        engine.selection = .caret(at: 3)
        #expect(engine.typingAttributes.bold)

        // A caret move (arrow keys, tap-to-place) moves the selection behind
        // the engine's back in production; `typingAttributes` goes stale
        // until `synchronizeSelection()` runs.
        concrete.simulateSelectionChange(.caret(at: 6))
        #expect(engine.typingAttributes.bold) // stale: still reflects offset 3

        engine.synchronizeSelection()
        #expect(engine.typingAttributes.bold == false)

        concrete.simulateSelectionChange(.caret(at: 1))
        #expect(engine.typingAttributes.bold == false) // stale: still reflects offset 6

        engine.synchronizeSelection()
        #expect(engine.typingAttributes.bold)
    }

    /// Both hooks, exercised through `simulateSelectionChange`/
    /// `simulateTextChange` so neither call refreshes `typingAttributes` on
    /// its own — only the hook itself can. `synchronizeSelection()` must drop
    /// the pending style the moment the caret is (really) in a different
    /// empty block; `synchronizeFromTextView()` must both preserve it across
    /// an external mutation that leaves the caret's still-empty block
    /// unchanged, and drop it when that mutation is paired with a move to a
    /// different empty block.
    @Test func pendingBlockStyleRuleHoldsAcrossBothSynchronizationHooks() {
        let concrete = InMemoryEditorEngine()
        let engine: EditorEngine = concrete
        engine.text = AttributedString("\n\n") // three empty blocks: offsets 0, 1, 2
        engine.selection = .caret(at: 0)
        engine.apply(.toggleHeading(1))
        #expect(engine.typingAttributes.blockStyle == .heading(1))

        // `synchronizeSelection()`: a caret move to a *different* empty block
        // must drop the pending style — and only the hook does that, not the
        // simulated move itself.
        concrete.simulateSelectionChange(.caret(at: 1))
        #expect(engine.typingAttributes.blockStyle == .heading(1)) // stale: hook hasn't run
        engine.synchronizeSelection()
        #expect(engine.typingAttributes.blockStyle == nil)
        #expect(engine.formatState.blockStyle == .paragraph)

        // Re-establish a pending style in this (now current) empty block,
        // then exercise `synchronizeFromTextView()`: an external mutation
        // that leaves the caret's block unchanged and still empty must
        // preserve the pending style once the hook re-derives it.
        engine.apply(.toggleHeading(2))
        #expect(engine.typingAttributes.blockStyle == .heading(2))
        concrete.simulateTextChange(AttributedString("\n\n")) // unchanged content
        #expect(engine.typingAttributes.blockStyle == .heading(2)) // stale, pre-hook (trivially, but exercised below)
        engine.synchronizeFromTextView()
        #expect(engine.typingAttributes.blockStyle == .heading(2))

        // An external mutation that fills in the caret's block — it is no
        // longer empty — must drop the pending style, since D13's pending
        // role only ever applies to a still-empty block. Only the hook
        // re-derives this; the simulated mutation alone leaves
        // `typingAttributes` untouched.
        concrete.simulateTextChange(AttributedString("H\n"))
        #expect(engine.typingAttributes.blockStyle == .heading(2)) // stale: hook hasn't run
        engine.synchronizeFromTextView()
        #expect(engine.typingAttributes.blockStyle == nil)
        #expect(engine.formatState.blockStyle == .paragraph)
    }

    // MARK: - Return key (M4 decision D5), through the seam

    @Test func insertNewlineContinuesAListThroughTheSeam() {
        let engine = engine(Sem.block("one", .listItem(.unordered, depth: 0)))
        engine.selection = .caret(at: 3)
        engine.insertNewline()
        #expect(String(engine.text.characters) == "one\n")
        #expect(engine.selection == .caret(at: 4))
        #expect(engine.typingAttributes.blockStyle == .listItem(.unordered, depth: 0))
        #expect(engine.formatState.blockStyle == .listItem(.unordered, depth: 0))
    }

    @Test func insertNewlineAtTheEndOfAHeadingStartsAParagraph() {
        let engine = engine(Sem.block("Title", .heading(1)))
        engine.selection = .caret(at: 5)
        engine.insertNewline()
        #expect(engine.formatState.blockStyle == .paragraph)
    }

    @Test func insertNewlineInAnEmptyListItemLeavesTheList() {
        let engine = engine(AttributedString())
        engine.selection = .caret(at: 0)
        engine.apply(.toggleList(.unordered))
        #expect(engine.formatState.blockStyle == .listItem(.unordered, depth: 0))
        engine.insertNewline()
        #expect(engine.text.characters.isEmpty)
        #expect(engine.formatState.blockStyle == .paragraph)
    }
}
