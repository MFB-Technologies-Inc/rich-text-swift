// RichTextEditorModelTests.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
import RichTextCore
@testable import RichTextEditorUI
import RichTextEngine
import Testing

@MainActor
struct RichTextEditorModelTests {
    private func attached() -> (RichTextEditorModel, FakeEditorEngine) {
        let model = RichTextEditorModel()
        let engine = FakeEditorEngine()
        model.attach(engine)
        return (model, engine)
    }

    @Test func aDetachedModelReportsDefaults() {
        let model = RichTextEditorModel()
        #expect(model.formatState == FormatState())
        #expect(model.text == AttributedString())
        // Commands before attachment are dropped, not crashes.
        model.apply(.toggleBold)
        #expect(model.formatState == FormatState())
    }

    @Test func attachingPublishesTheEnginesState() async {
        let model = RichTextEditorModel()
        let engine = FakeEditorEngine()
        engine.text = AttributedString("hello")
        engine.formatState.italic = .on
        model.attach(engine)
        // `text` is a pass-through to the engine, so it's correct immediately;
        // `formatState` is now deferred (see `scheduleRefresh()`) since attach
        // is reached from SwiftUI's view-update phase in production.
        #expect(model.text == AttributedString("hello"))
        await settle()
        #expect(model.formatState.italic == .on)
    }

    @Test func applyForwardsToTheEngineAndRepublishesState() {
        let (model, engine) = attached()
        model.apply(.toggleBold)
        #expect(engine.appliedCommands == [.toggleBold])
        #expect(model.formatState.bold == .on)
    }

    @Test func setTextForwardsToTheEngine() {
        let (model, engine) = attached()
        model.setText(AttributedString("new"))
        #expect(engine.text == AttributedString("new"))
        #expect(model.text == AttributedString("new"))
    }

    @Test func insertNewlineForwardsToTheEngine() {
        let (model, engine) = attached()
        model.insertNewline()
        #expect(engine.newlineCount == 1)
    }

    @Test func synchronizationHooksForwardAndRepublish() async {
        let (model, engine) = attached()
        model.synchronizeSelection()
        #expect(engine.selectionSyncCount == 1)
        // `synchronizeSelection()` now defers its republish (Fix 1: it's
        // reachable from the view-update phase via a reentrant
        // `textViewDidChangeSelection`, see `scheduleRefresh()`), so the
        // proof that the model actually republished `formatState` after the
        // hook — rather than merely forwarding the call — has to land after
        // the hop.
        await settle()
        #expect(model.formatState.italic == .on)

        model.synchronizeFromTextView()
        #expect(engine.textViewSyncCount == 1)
        #expect(model.formatState.strikethrough == .on)
    }

    @Test func refreshPicksUpStateChangedBehindTheModelsBack() {
        let (model, engine) = attached()
        engine.formatState.underline = .mixed
        #expect(model.formatState.underline == .off)
        model.refresh()
        #expect(model.formatState.underline == .mixed)
    }

    // MARK: - Deferred republication (M5 decision D8)

    @Test func setTextDoesNotRepublishSynchronously() async {
        let (model, engine) = attached()
        engine.formatState.bold = .on

        // `setText` is called from `updateUIView`, i.e. during SwiftUI's
        // view-update phase, where mutating observed state is illegal.
        model.setText(AttributedString("new"))
        #expect(model.formatState.bold == .off)

        await settle()
        #expect(model.formatState.bold == .on)
    }

    @Test func attachDoesNotRepublishSynchronously() async {
        let model = RichTextEditorModel()
        let engine = FakeEditorEngine()
        engine.formatState.italic = .on

        model.attach(engine)
        #expect(model.formatState.italic == .off)

        await settle()
        #expect(model.formatState.italic == .on)
    }

    @Test func applyStillRepublishesSynchronously() {
        // A user-driven command is NOT in the update phase, and a toolbar must
        // see its own effect immediately — no deferral here.
        let (model, engine) = attached()
        model.apply(.toggleBold)
        #expect(engine.appliedCommands == [.toggleBold])
        #expect(model.formatState.bold == .on)
    }

    @Test func scheduleRefreshPicksUpStateChangedBehindTheModelsBack() async {
        let (model, engine) = attached()
        engine.formatState.underline = .mixed
        model.scheduleRefresh()
        #expect(model.formatState.underline == .off)

        await settle()
        #expect(model.formatState.underline == .mixed)
    }

    // MARK: - synchronizeSelection's indirect update-phase path (Fix 1)

    /// `synchronizeSelection()` is reachable not just from a genuine
    /// user-driven caret move but also *synchronously* from inside
    /// `setText(_:)` -> `render(restoring:)`'s selection clamp (a
    /// `textViewDidChangeSelection` callback reentered mid-push). That makes
    /// it a view-update-phase caller in production, so it must defer like
    /// `setText`/`attach` do, not publish synchronously.
    @Test func synchronizeSelectionDoesNotRepublishSynchronously() async {
        let (model, engine) = attached()
        engine.formatState.italic = .on

        model.synchronizeSelection()
        #expect(model.formatState.italic == .off)

        await settle()
        #expect(model.formatState.italic == .on)
    }

    /// `scheduleRefresh()` coalesces: several calls inside one main-actor turn
    /// must settle to the engine's *current* state after a single hop, not
    /// leave anything stale or double-apply. This does not prove only one
    /// `Task` was scheduled (the hop count is not observable from here — the
    /// fake engine has no way to count `formatState` reads distinctly from
    /// other engine access), only that the coalesced result is correct.
    @Test func scheduleRefreshCoalescesMultipleCallsInOneTurn() async {
        let (model, engine) = attached()

        engine.formatState.bold = .on
        model.scheduleRefresh()
        engine.formatState.italic = .on
        model.scheduleRefresh()
        engine.formatState.underline = .mixed
        model.scheduleRefresh()

        #expect(model.formatState == FormatState())

        await settle()
        #expect(model.formatState.bold == .on)
        #expect(model.formatState.italic == .on)
        #expect(model.formatState.underline == .mixed)
    }
}
