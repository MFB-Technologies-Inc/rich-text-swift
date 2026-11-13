// FormatPanelControlTests.swift
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

    @MainActor
    struct FormatPanelControlTests {
        private typealias Style = FormatPanelControl.Style

        private func attached(blockStyle: BlockStyle? = .paragraph) async -> (RichTextEditorModel, FakeEditorEngine) {
            let model = RichTextEditorModel()
            let engine = FakeEditorEngine()
            engine.formatState.blockStyle = blockStyle
            model.attach(engine)
            await settle()
            return (model, engine)
        }

        @Test func thePanelOffersBodyThenEveryHeadingLevelInOrder() {
            #expect(Style.allCases == [.body, .heading(.h1), .heading(.h2), .heading(.h3)])
            #expect(Style.allCases.map(\.title) == ["Body", "Heading 1", "Heading 2", "Heading 3"])
        }

        @Test func eachRowPreviewsItsThemeFont() {
            #expect(Style.body.appearance == Theme.default.paragraph)
            #expect(Style.heading(.h1).appearance == Theme.default.heading1)
            #expect(Style.heading(.h2).appearance == Theme.default.heading2)
            #expect(Style.heading(.h3).appearance == Theme.default.heading3)
        }

        @Test func pickingALevelSetsThatHeading() async {
            let (model, engine) = await attached()
            let panel = FormatPanelControl(model: model, isActive: false)

            panel.select(.heading(.h2))

            #expect(engine.appliedCommands == [.setBlockStyle(.heading(2))])
        }

        @Test func pickingBodySetsAParagraph() async {
            let (model, engine) = await attached(blockStyle: .heading(1))
            let panel = FormatPanelControl(model: model, isActive: true)

            panel.select(.body)

            #expect(engine.appliedCommands == [.setBlockStyle(.paragraph)])
        }

        @Test func theSelectedHeadingIsChecked() async {
            let (model, _) = await attached(blockStyle: .heading(3))
            let panel = FormatPanelControl(model: model, isActive: true)

            #expect(Style.allCases.filter(panel.isChecked) == [.heading(.h3)])
        }

        @Test func aParagraphChecksBody() async {
            let (model, _) = await attached(blockStyle: .paragraph)
            let panel = FormatPanelControl(model: model, isActive: false)

            #expect(Style.allCases.filter(panel.isChecked) == [.body])
        }

        @Test func aListItemOrMixedSelectionChecksNothing() async {
            for blockStyle in [BlockStyle.listItem(.unordered, depth: 0), nil] {
                let (model, _) = await attached(blockStyle: blockStyle)
                let panel = FormatPanelControl(model: model, isActive: false)

                #expect(Style.allCases.filter(panel.isChecked).isEmpty)
            }
        }

        @Test func anEndToEndPickReachesTheDocument() async {
            let model = RichTextEditorModel()
            let root = RichTextEditor(text: .constant(RichTextHTML.decode("<p>hello</p>")))
                .richTextToolbar(.html, model: model)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
            window.rootViewController = UIHostingController(rootView: root)
            window.makeKeyAndVisible()
            window.layoutIfNeeded()
            await settle()
            let panel = FormatPanelControl(model: model, isActive: false)

            panel.select(.heading(.h2))
            #expect(RichTextHTML.encode(model.text) == "<h2>hello</h2>")
            #expect(RichTextControl.format.isActive(in: model.formatState))

            // Picking the style it already has leaves it alone, unlike the
            // `.heading(_:)` toggle buttons.
            panel.select(.heading(.h2))
            #expect(RichTextHTML.encode(model.text) == "<h2>hello</h2>")

            panel.select(.body)
            #expect(RichTextHTML.encode(model.text) == "<p>hello</p>")
            #expect(RichTextControl.format.isActive(in: model.formatState) == false)
        }
    }
#endif
