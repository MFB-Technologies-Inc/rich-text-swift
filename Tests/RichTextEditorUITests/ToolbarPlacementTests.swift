// ToolbarPlacementTests.swift
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

    /// `placement` decides whether the bar sits above or below the editor.
    @MainActor
    struct ToolbarPlacementTests {
        private func hosted(placement: RichTextToolbarPlacement) async -> UIWindow {
            let model = RichTextEditorModel()
            let root = RichTextEditor(text: .constant(RichTextHTML.decode("<p>hello</p>")))
                .richTextToolbar(.default, placement: placement, model: model)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
            window.rootViewController = UIHostingController(rootView: root)
            window.makeKeyAndVisible()
            window.layoutIfNeeded()
            await settle()
            window.layoutIfNeeded()
            return window
        }

        private func descendants(of view: UIView) -> [UIView] {
            [view] + view.subviews.flatMap { descendants(of: $0) }
        }

        /// The editor is a `UITextView`; the bar is the scroll view that is *not*
        /// one (a `UITextView` is itself a `UIScrollView`).
        private func editorAndBar(in window: UIWindow) -> (editor: UIView, bar: UIView)? {
            let all = descendants(of: window.rootViewController!.view)
            guard let editor = all.first(where: { $0 is UITextView }),
                  let bar = all.first(where: { $0 is UIScrollView && !($0 is UITextView) })
            else { return nil }
            return (editor, bar)
        }

        private func midY(_ view: UIView, in window: UIWindow) -> CGFloat {
            view.convert(view.bounds, to: window).midY
        }

        @Test func bottomIsTheDefaultAndPutsTheBarBelowTheEditor() async throws {
            let window = await hosted(placement: .bottom)
            let pair = try #require(editorAndBar(in: window))
            #expect(midY(pair.bar, in: window) > midY(pair.editor, in: window))
        }

        @Test func topPutsTheBarAboveTheEditor() async throws {
            let window = await hosted(placement: .top)
            let pair = try #require(editorAndBar(in: window))
            #expect(midY(pair.bar, in: window) < midY(pair.editor, in: window))
        }

        @Test func theEditorStillAdoptsTheInjectedModelWhenTheBarIsOnTop() async {
            // The environment injection must not depend on the bar's position.
            let model = RichTextEditorModel()
            let root = RichTextEditor(text: .constant(RichTextHTML.decode("<p>hello</p>")))
                .richTextToolbar(.default, placement: .top, model: model)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
            window.rootViewController = UIHostingController(rootView: root)
            window.makeKeyAndVisible()
            window.layoutIfNeeded()
            await settle()
            window.layoutIfNeeded()
            await settle()

            #expect(String(model.text.characters) == "hello")
            model.apply(.toggleHeading(1))
            #expect(RichTextHTML.encode(model.text) == "<h1>hello</h1>")
        }

        @Test func placementDefaultsToBottom() {
            // The default is part of the public API's contract, not an accident of
            // how the tests happen to call it.
            let modifier = RichTextToolbarModifier(controls: .default)
            #expect(modifier.placement == .bottom)
        }
    }
#endif
