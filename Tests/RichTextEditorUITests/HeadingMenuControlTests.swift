// HeadingMenuControlTests.swift
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
    struct HeadingMenuControlTests {
        private func attached(blockStyle: BlockStyle? = .paragraph) async -> (RichTextEditorModel, FakeEditorEngine) {
            let model = RichTextEditorModel()
            let engine = FakeEditorEngine()
            engine.formatState.blockStyle = blockStyle
            model.attach(engine)
            await settle()
            return (model, engine)
        }

        @Test func theMenuOffersBodyThenEveryHeadingLevelInOrder() {
            #expect(HeadingMenuControl.Choice.allCases == [.body, .heading(.h1), .heading(.h2), .heading(.h3)])
            #expect(HeadingMenuControl.Choice.allCases.map(\.title) == ["Body", "Heading 1", "Heading 2", "Heading 3"])
        }

        @Test func pickingALevelSetsThatHeading() async {
            let (model, engine) = await attached()
            let menu = HeadingMenuControl(model: model, isActive: false)

            menu.select(.heading(.h2))

            #expect(engine.appliedCommands == [.setBlockStyle(.heading(2))])
        }

        @Test func pickingBodySetsAParagraph() async {
            let (model, engine) = await attached(blockStyle: .heading(1))
            let menu = HeadingMenuControl(model: model, isActive: true)

            menu.select(.body)

            #expect(engine.appliedCommands == [.setBlockStyle(.paragraph)])
        }

        @Test func theSelectedHeadingIsCheckedAndShownInTheLabel() async {
            let (model, _) = await attached(blockStyle: .heading(3))
            let menu = HeadingMenuControl(model: model, isActive: true)

            #expect(HeadingMenuControl.Choice.allCases.filter(menu.isChecked) == [.heading(.h3)])
            #expect(menu.labelText == "H3")
        }

        @Test func aParagraphChecksBodyAndShowsTheRestingLabel() async {
            let (model, _) = await attached(blockStyle: .paragraph)
            let menu = HeadingMenuControl(model: model, isActive: false)

            #expect(HeadingMenuControl.Choice.allCases.filter(menu.isChecked) == [.body])
            #expect(menu.labelText == "H")
        }

        @Test func aListItemOrMixedSelectionChecksNothing() async {
            for blockStyle in [BlockStyle.listItem(.unordered, depth: 0), nil] {
                let (model, _) = await attached(blockStyle: blockStyle)
                let menu = HeadingMenuControl(model: model, isActive: false)

                #expect(HeadingMenuControl.Choice.allCases.filter(menu.isChecked).isEmpty)
                #expect(menu.labelText == "H")
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
            let menu = HeadingMenuControl(model: model, isActive: false)

            menu.select(.heading(.h2))
            #expect(RichTextHTML.encode(model.text) == "<h2>hello</h2>")
            #expect(RichTextControl.headings.isActive(in: model.formatState))

            // Picking the level it already has leaves it alone, unlike the
            // `.heading(_:)` toggle buttons.
            menu.select(.heading(.h2))
            #expect(RichTextHTML.encode(model.text) == "<h2>hello</h2>")

            menu.select(.body)
            #expect(RichTextHTML.encode(model.text) == "<p>hello</p>")
            #expect(RichTextControl.headings.isActive(in: model.formatState) == false)
        }
    }
#endif
