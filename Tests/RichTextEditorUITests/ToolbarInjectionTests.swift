// ToolbarInjectionTests.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
import RichTextCore
import Testing

#if os(iOS)
    @testable import RichTextEditorUI
    import RichTextEngine
    import SwiftUI
    import UIKit

    /// The environment contract between the toolbar and the editor: the toolbar modifier
    /// creates the model and injects it *downward*, and `RichTextEditor` adopts it
    /// instead of its own. Unverifiable until a toolbar existed to do the injecting.
    @MainActor
    struct ToolbarInjectionTests {
        private func findTextView(in view: UIView) -> UITextView? {
            if let textView = view as? UITextView {
                return textView
            }
            for sub in view.subviews {
                if let found = findTextView(in: sub) {
                    return found
                }
            }
            return nil
        }

        /// Hosts `RichTextEditor(text:).richTextToolbar(_:model:)` in a real key
        /// window and returns the window plus the model the test injected.
        private func hostEditorWithToolbar(
            html: String,
            model: RichTextEditorModel
        ) -> UIWindow {
            let document = RichTextHTML.decode(html)
            let root = RichTextEditor(text: .constant(document))
                .richTextToolbar([.bold, .textColor, .unorderedList, .heading(.h1)], model: model)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
            window.rootViewController = UIHostingController(rootView: root)
            window.makeKeyAndVisible()
            window.layoutIfNeeded()
            return window
        }

        @Test func theEditorAdoptsTheInjectedModel() async {
            let model = RichTextEditorModel()
            let window = hostEditorWithToolbar(html: "<p>hello</p>", model: model)
            await settle()
            window.layoutIfNeeded()
            await settle()

            // If injection failed, the editor would have used its own model and
            // ours would still have no engine — so `text` would be empty.
            #expect(String(model.text.characters) == "hello")
            #expect(RichTextHTML.encode(model.text) == "<p>hello</p>")
        }

        @Test func aCommandThroughTheInjectedModelReachesTheTextView() async {
            let model = RichTextEditorModel()
            let window = hostEditorWithToolbar(html: "<p>hello</p>", model: model)
            await settle()
            window.layoutIfNeeded()
            await settle()

            // A block command applies at the caret, so no selection setup is needed.
            model.apply(.toggleHeading(1))

            #expect(RichTextHTML.encode(model.text) == "<h1>hello</h1>")
            // The assertions above are load-bearing *because* they run
            // synchronously, right after `model.apply(_:)` and with no `await` in
            // between: `hostEditorWithToolbar` binds `text` with `.constant`, so
            // if a later `updateUIView` ran (e.g. after an `await settle()`
            // inserted here), its `pushIfNeeded` would push the constant binding's
            // original, unheaded document straight back over the applied change.
            // Do not add an `await` between `apply` and these checks.
            let textView = findTextView(in: window)
            // The rendered storage really changed: an H1 is larger than body text.
            let font = textView?.textStorage.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
            #expect(font.map { Double($0.pointSize) } == Theme.default.heading1.fontSize)
        }

        @Test func theInjectedModelPublishesStateForTheToolbar() async {
            let model = RichTextEditorModel()
            // Hosting an existing `<h1>` (rather than the default paragraph) makes
            // the pre-apply assertions below discriminating: `FormatState()`'s
            // default `blockStyle` is already `.paragraph`, and
            // `RichTextEditorModel.refresh()` falls back to `FormatState()` when
            // there is no attached engine — so asserting `.paragraph` on a
            // freshly-created, un-injected model would pass vacuously even with
            // injection completely broken. `.heading(1)` can only come from an
            // engine that actually parsed this document.
            let window = hostEditorWithToolbar(html: "<h1>hello</h1>", model: model)
            await settle()
            window.layoutIfNeeded()
            await settle()

            #expect(model.formatState.blockStyle == .heading(1))
            #expect(RichTextControl.heading(.h1).isActive(in: model.formatState))

            model.apply(.toggleHeading(1))
            #expect(model.formatState.blockStyle == .paragraph)
            #expect(RichTextControl.heading(.h1).isActive(in: model.formatState) == false)
        }

        /// Smoke test for the public, no-injected-model overload: proves the
        /// public modifier hosts an editor at all without crashing or losing the
        /// document. This does NOT prove the modifier creates its own model (that
        /// claim needs the injected-model path above) — `textStorage.string ==
        /// "hi"` here is equally satisfied by `RichTextEditorRepresentable
        /// .makeUIView` setting `engine.text = text` directly from the binding,
        /// which happens whether or not model injection works at all.
        @Test func thePublicModifierHostsAnEditorWithoutCrashing() async {
            let root = RichTextEditor(text: .constant(RichTextHTML.decode("<p>hi</p>")))
                .richTextToolbar([.bold, .heading(.h1)])
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
            window.rootViewController = UIHostingController(rootView: root)
            window.makeKeyAndVisible()
            window.layoutIfNeeded()
            await settle()

            let textView = findTextView(in: window)
            #expect(textView?.textStorage.string == "hi")
        }

        /// Closes the gap the editor-side tests above don't cover: they all drive
        /// `model.apply(...)` on the model the *test* holds directly, never on
        /// the bar the modifier actually builds — so a modifier that silently
        /// handed the toolbar a different model would leave every one of those
        /// tests green while every button in the shipped product was dead. This
        /// asserts the modifier's `toolbar` — the one property that builds the
        /// `RichTextToolbar` it displays — holds *this* injected model by
        /// identity.
        @Test func theModifierBuildsItsToolbarAroundTheInjectedModel() {
            let model = RichTextEditorModel()
            let modifier = RichTextToolbarModifier(controls: [.bold], model: model)
            #expect(modifier.toolbar.model === model)
        }
    }
#endif
