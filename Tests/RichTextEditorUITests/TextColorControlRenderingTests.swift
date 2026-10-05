// TextColorControlRenderingTests.swift
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

    /// Coverage for the `.textColor` control now that it is the system
    /// `ColorPicker`.
    ///
    /// **What is no longer verifiable, and why.** The previous custom palette drew
    /// its swatches as SwiftUI shapes, so `ImageRenderer` could render it and a
    /// test could assert each preset's RGB appeared in the pixels — which is how a
    /// real defect was caught (a `Menu` renders item images as monochrome
    /// templates, so every swatch drew black). `ColorPicker` is UIKit-backed
    /// (`UIColorWell`), and `ImageRenderer` renders it as SwiftUI's
    /// unsupported-view placeholder, so pixel assertions about the swatch's color
    /// are impossible here. What remains testable is that the real native control
    /// is instantiated and sized, plus the command behavior below.
    @MainActor
    struct TextColorControlRenderingTests {
        private func attached(textColor: RichTextColor?) async -> RichTextEditorModel {
            let model = RichTextEditorModel()
            let engine = FakeEditorEngine()
            engine.formatState.textColor = textColor
            model.attach(engine)
            await settle()
            return model
        }

        private func hosted(_ view: some View) -> UIWindow {
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
            window.rootViewController = UIHostingController(rootView: view)
            window.makeKeyAndVisible()
            window.layoutIfNeeded()
            return window
        }

        private func descendants(of view: UIView) -> [UIView] {
            [view] + view.subviews.flatMap { descendants(of: $0) }
        }

        @Test func theControlIsTheSystemColorWell() async throws {
            // Fails if the control is ever swapped back to a custom SwiftUI view:
            // only the native picker puts a UIColorWell in the hierarchy.
            let model = await attached(textColor: RichTextColor(red: 0, green: 122, blue: 255))
            let window = hosted(TextColorControl(model: model, isActive: false))
            await settle()
            window.layoutIfNeeded()

            let classNames = try descendants(of: #require(window.rootViewController?.view))
                .map { String(describing: type(of: $0)) }
            #expect(classNames.contains { $0.contains("ColorWell") }, "found: \(classNames)")
        }

        @Test func theControlLaysOutWithinTheToolbarChrome() async throws {
            let model = await attached(textColor: nil)
            let window = hosted(TextColorControl(model: model, isActive: false))
            await settle()
            window.layoutIfNeeded()

            // The control is constrained to the 44pt chrome every other control
            // uses, so nothing it renders may exceed that.
            let colorWell = try descendants(of: #require(window.rootViewController?.view))
                .first { String(describing: type(of: $0)).contains("ColorWell") }
            let size = colorWell?.bounds.size
            #expect(size != nil)
            #expect((size?.width ?? 999) <= 44)
            #expect((size?.height ?? 999) <= 44)
        }

        @Test func aSelectionWithNoColorStillLaysOut() async {
            let model = await attached(textColor: nil)
            let window = hosted(TextColorControl(model: model, isActive: false))
            await settle()
            window.layoutIfNeeded()
            #expect(window.rootViewController?.view.subviews.isEmpty == false)
        }
    }
#endif
