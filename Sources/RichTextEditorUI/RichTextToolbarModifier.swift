// RichTextToolbarModifier.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

#if os(iOS)
    import SwiftUI

    /// Adds the declarative toolbar above or below an editor (`placement`, default
    /// `.bottom`), and owns the view model both halves share.
    ///
    /// The ownership direction is forced by SwiftUI (M5 decision D3, M4 decision
    /// D3): `.environment(_:)` reaches only a view's *descendants*, and
    /// `RichTextEditor(text: $doc).richTextToolbar([...])` places this modifier
    /// *above* the editor. So the editor cannot hand a model up to the toolbar —
    /// this modifier creates it and injects it *down* onto the editor, which reads
    /// an optional injected model and falls back to its own when there is none.
    /// Degenerate usages, both outside documented v1 usage (not guarded against,
    /// just noted here):
    ///
    /// - **Two `.richTextToolbar` modifiers stacked on one editor.** Each creates
    ///   its own model and `.environment(_:)`s it downward; the inner modifier's
    ///   environment value shadows the outer one for everything below it,
    ///   including the editor. The editor ends up attached to the *inner*
    ///   modifier's model, so the outer bar's model is never attached to an
    ///   engine and its bar is dead.
    /// - **Two `RichTextEditor`s under one `.richTextToolbar`.** Both read the
    ///   same injected model from the environment and both attach it to their own
    ///   engine; the second `attach(_:)` call wins, so the bar ends up reflecting
    ///   (and driving) whichever editor attached last, not necessarily the one
    ///   the user is looking at.
    struct RichTextToolbarModifier: ViewModifier {
        let controls: [RichTextControl]
        let placement: RichTextToolbarPlacement
        @State private var model: RichTextEditorModel

        /// - Parameter model: Adopted only at this view identity's *first*
        ///   initialization. `@State(initialValue:)` seeds SwiftUI's per-identity
        ///   storage box once; SwiftUI persists that box across re-renders and
        ///   discards the `initialValue` argument on every init after the first,
        ///   so re-rendering this modifier with a different `model` for the same
        ///   view identity keeps the original one. (Both halves — the editor and
        ///   the bar — still read the same `@State` box, so this is not a
        ///   split-model bug, just a stale-adoption one.) To test or use a
        ///   different model, host a fresh view hierarchy rather than swapping
        ///   the argument on a live one.
        init(
            controls: [RichTextControl],
            placement: RichTextToolbarPlacement = .bottom,
            model: RichTextEditorModel? = nil
        ) {
            self.controls = controls
            self.placement = placement
            _model = State(initialValue: model ?? RichTextEditorModel())
        }

        /// The one place `RichTextToolbar` is constructed, so a test can assert
        /// which model it was built around without needing a live SwiftUI render
        /// pass (see `ToolbarInjectionTests.theModifierBuildsItsToolbarAroundTheInjectedModel`).
        var toolbar: RichTextToolbar {
            RichTextToolbar(controls: controls, model: model)
        }

        func body(content: Content) -> some View {
            VStack(spacing: 0) {
                // The editor keeps `.environment(model)` in both orders: it is the
                // injection that makes the editor adopt this modifier's model, not
                // a side effect of position.
                if placement == .top {
                    toolbar
                    content
                        .environment(model)
                } else {
                    content
                        .environment(model)
                    toolbar
                }
            }
        }
    }

    extension View {
        /// Attaches the built-in rich text toolbar, showing exactly the controls
        /// given, in the order given.
        ///
        /// ```swift
        /// // No arguments: the seven-control default (inline formatting + lists).
        /// RichTextEditor(text: $document)
        ///     .richTextToolbar()
        ///
        /// // A named preset: `.default` plus the H1–H3 heading controls.
        /// RichTextEditor(text: $document)
        ///     .richTextToolbar(.html)
        ///
        /// // Above the editor instead of below.
        /// RichTextEditor(text: $document)
        ///     .richTextToolbar(.html, placement: .top)
        ///
        /// // An explicit array, in exactly the order given.
        /// RichTextEditor(text: $document)
        ///     .richTextToolbar([.bold, .italic, .underline, .strikethrough,
        ///                       .textColor, .unorderedList, .orderedList,
        ///                       .heading(.h1), .heading(.h2), .heading(.h3)])
        /// ```
        ///
        /// `.default` is `[.bold, .italic, .underline, .strikethrough, .textColor,
        /// .unorderedList, .orderedList]` — seven controls, which also happens to
        /// fit a phone's width without scrolling. `.html` is `.default` plus
        /// `.heading(.h1)`, `.heading(.h2)`, `.heading(.h3)` — the full v1
        /// control set.
        ///
        /// The bar sits below the editor and rides above the keyboard, since
        /// SwiftUI's keyboard safe area insets it (M5 decision D2).
        public func richTextToolbar(
            _ controls: [RichTextControl] = .default,
            placement: RichTextToolbarPlacement = .bottom
        ) -> some View {
            modifier(RichTextToolbarModifier(controls: controls, placement: placement))
        }
    }

    extension View {
        /// Test seam: attach the toolbar around a model the caller already holds,
        /// so a test can observe the state the editor and toolbar actually share.
        /// The public overload always creates its own.
        ///
        /// Like the modifier's `init`, `model` is adopted only at first
        /// initialization for a given view identity — re-hosting this modifier
        /// with a different `model` on a *live* hierarchy keeps the first one
        /// (see `RichTextToolbarModifier.init`). Host a fresh hierarchy per model
        /// under test rather than swapping this argument in place.
        func richTextToolbar(
            _ controls: [RichTextControl],
            placement: RichTextToolbarPlacement = .bottom,
            model: RichTextEditorModel
        ) -> some View {
            modifier(RichTextToolbarModifier(controls: controls, placement: placement, model: model))
        }
    }
#endif
