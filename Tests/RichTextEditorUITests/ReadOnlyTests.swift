// ReadOnlyTests.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
import RichTextCore
import Testing

#if os(iOS)
    @testable import RichTextEditorUI
    @testable import RichTextEngine
    import SwiftUI
    import UIKit

    /// `RichTextEditor(text:isEditable:)` — read-only must hold at every route
    /// into the document, not just in the text view: a toolbar tap, the color
    /// control, and a Return keystroke all go through the model.
    @MainActor
    struct ReadOnlyTests {
        private func hosted(isEditable: Bool) async -> (UIWindow, RichTextEditorModel) {
            let model = RichTextEditorModel()
            let root = RichTextEditor(text: .constant(RichTextHTML.decode("<p>hello</p>")), isEditable: isEditable)
                .richTextToolbar(.html, model: model)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
            window.rootViewController = UIHostingController(rootView: root)
            window.makeKeyAndVisible()
            window.layoutIfNeeded()
            await settle()
            window.layoutIfNeeded()
            await settle()
            return (window, model)
        }

        private func textView(in view: UIView) -> UITextView? {
            if let textView = view as? UITextView {
                return textView
            }
            for subview in view.subviews {
                if let found = textView(in: subview) {
                    return found
                }
            }
            return nil
        }

        @Test func editableIsTheDefault() {
            let model = RichTextEditorModel()
            #expect(model.isEditable)
        }

        @Test func aReadOnlyEditorsTextViewRefusesEditing() async throws {
            let (window, _) = await hosted(isEditable: false)
            #expect(try textView(in: #require(window.rootViewController?.view))?.isEditable == false)
        }

        @Test func anEditableEditorsTextViewAllowsEditing() async throws {
            let (window, _) = await hosted(isEditable: true)
            #expect(try textView(in: #require(window.rootViewController?.view))?.isEditable == true)
        }

        @Test func aReadOnlyModelRefusesCommands() async {
            let (_, model) = await hosted(isEditable: false)
            let before = model.text
            model.apply(.toggleHeading(1))
            #expect(model.text == before)
            #expect(RichTextHTML.encode(model.text) == "<p>hello</p>")
        }

        @Test func aReadOnlyModelRefusesReturn() async {
            let (_, model) = await hosted(isEditable: false)
            let before = model.text
            model.insertNewline()
            #expect(model.text == before)
        }

        @Test func aReadOnlyToolbarTapDoesNothing() async {
            let (_, model) = await hosted(isEditable: false)
            let toolbar = RichTextToolbar(controls: .html, model: model)
            toolbar.tap(.bold)
            #expect(RichTextHTML.encode(model.text) == "<p>hello</p>")
        }

        @Test func aReadOnlyColorControlDoesNothing() async {
            let (_, model) = await hosted(isEditable: false)
            TextColorControl(model: model, isActive: false)
                .select(RichTextColor(red: 255, green: 59, blue: 48))
            #expect(RichTextHTML.encode(model.text) == "<p>hello</p>")
        }

        /// A plain `Bool` is enough for live changes — no `Binding` required.
        /// When the consumer's value changes, its body re-evaluates, the editor is
        /// reconstructed, and `updateUIView` applies the new value to both the
        /// text view and the model. (A `Binding` would imply the editor writes the
        /// value back, which it never does.)
        @Test func togglingEditabilityOnALiveViewTakesEffect() async throws {
            let settings = EditabilitySettings()
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
            window.rootViewController = UIHostingController(rootView: EditabilityWrapper(settings: settings))
            window.makeKeyAndVisible()
            window.layoutIfNeeded()
            await settle()
            #expect(try textView(in: #require(window.rootViewController?.view))?.isEditable == true)

            settings.isEditable = false
            await settle()
            window.layoutIfNeeded()
            await settle()
            #expect(try textView(in: #require(window.rootViewController?.view))?.isEditable == false)

            settings.isEditable = true
            await settle()
            window.layoutIfNeeded()
            await settle()
            #expect(try textView(in: #require(window.rootViewController?.view))?.isEditable == true)
        }

        @Test func anEditableEditorStillAcceptsCommands() async {
            let (_, model) = await hosted(isEditable: true)
            model.apply(.toggleHeading(1))
            #expect(RichTextHTML.encode(model.text) == "<h1>hello</h1>")
        }
    }

    /// File scope because `@Observable` cannot attach to a type declared inside a
    /// function.
    @MainActor
    @Observable final class EditabilitySettings {
        var isEditable = true
    }

    struct EditabilityWrapper: View {
        let settings: EditabilitySettings

        var body: some View {
            RichTextEditor(
                text: .constant(RichTextHTML.decode("<p>hello</p>")),
                isEditable: settings.isEditable
            )
        }
    }
#endif
