// RichTextControlTests.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
import RichTextCore
@testable import RichTextEditorUI
import RichTextEngine
import Testing

struct RichTextControlTests {
    // MARK: - Command mapping

    @Test func inlineControlsMapToTheirToggles() {
        #expect(RichTextControl.bold.command == .toggleBold)
        #expect(RichTextControl.italic.command == .toggleItalic)
        #expect(RichTextControl.underline.command == .toggleUnderline)
        #expect(RichTextControl.strikethrough.command == .toggleStrikethrough)
    }

    @Test func listControlsMapToTheirKind() {
        #expect(RichTextControl.unorderedList.command == .toggleList(.unordered))
        #expect(RichTextControl.orderedList.command == .toggleList(.ordered))
    }

    @Test func headingControlsMapToTheirLevel() {
        #expect(RichTextControl.heading(.h1).command == .toggleHeading(1))
        #expect(RichTextControl.heading(.h2).command == .toggleHeading(2))
        #expect(RichTextControl.heading(.h3).command == .toggleHeading(3))
    }

    @Test func theColorControlHasNoFixedCommand() {
        // The color comes from the system picker's own binding, not a fixed
        // command; picking black removes the color rather than applying it.
        #expect(RichTextControl.textColor.command == nil)
    }

    // MARK: - Active state

    @Test func anInlineControlIsActiveOnlyWhenFullyOn() {
        var state = FormatState()
        state.bold = .on
        #expect(RichTextControl.bold.isActive(in: state))

        state.bold = .off
        #expect(RichTextControl.bold.isActive(in: state) == false)

        // Mixed reads as inactive (M5 decision D6): tapping turns it fully on,
        // so an inactive button predicts its own tap.
        state.bold = .mixed
        #expect(RichTextControl.bold.isActive(in: state) == false)
    }

    @Test func eachInlineControlReadsItsOwnAttribute() {
        var state = FormatState()
        state.italic = .on
        #expect(RichTextControl.italic.isActive(in: state))
        #expect(RichTextControl.bold.isActive(in: state) == false)
        #expect(RichTextControl.underline.isActive(in: state) == false)
        #expect(RichTextControl.strikethrough.isActive(in: state) == false)
    }

    @Test func theColorControlIsActiveForAUniformColor() {
        var state = FormatState()
        state.textColor = RichTextColor(red: 255, green: 0, blue: 0)
        state.isTextColorMixed = false
        #expect(RichTextControl.textColor.isActive(in: state))
    }

    @Test func theColorControlIsInactiveWithNoColorOrAMixedOne() {
        var noColor = FormatState()
        noColor.textColor = nil
        #expect(RichTextControl.textColor.isActive(in: noColor) == false)

        var mixed = FormatState()
        mixed.textColor = nil
        mixed.isTextColorMixed = true
        #expect(RichTextControl.textColor.isActive(in: mixed) == false)
    }

    @Test func listControlsMatchTheirKindAtAnyDepth() {
        var state = FormatState()
        state.blockStyle = .listItem(.unordered, depth: 0)
        #expect(RichTextControl.unorderedList.isActive(in: state))
        #expect(RichTextControl.orderedList.isActive(in: state) == false)

        state.blockStyle = .listItem(.ordered, depth: 2)
        #expect(RichTextControl.orderedList.isActive(in: state))
        #expect(RichTextControl.unorderedList.isActive(in: state) == false)
    }

    @Test func headingControlsMatchOnlyTheirOwnLevel() {
        var state = FormatState()
        state.blockStyle = .heading(2)
        #expect(RichTextControl.heading(.h2).isActive(in: state))
        #expect(RichTextControl.heading(.h1).isActive(in: state) == false)
        #expect(RichTextControl.heading(.h3).isActive(in: state) == false)
    }

    @Test func blockControlsAreInactiveForAParagraph() {
        var state = FormatState()
        state.blockStyle = .paragraph
        #expect(RichTextControl.heading(.h1).isActive(in: state) == false)
        #expect(RichTextControl.unorderedList.isActive(in: state) == false)
        #expect(RichTextControl.orderedList.isActive(in: state) == false)
    }

    @Test func blockControlsAreInactiveForAMixedSelection() {
        // nil blockStyle means the selection spans differing roles.
        var state = FormatState()
        state.blockStyle = nil
        #expect(RichTextControl.heading(.h1).isActive(in: state) == false)
        #expect(RichTextControl.unorderedList.isActive(in: state) == false)
    }

    // MARK: - Presentation

    @Test func everyControlHasEitherASymbolOrAText() {
        // `.textColor` is deliberately excluded from the symbol/text pairing:
        // `RichTextToolbar.button(for:)` branches to `TextColorControl` before
        // ever consulting `systemImage`/`textLabel`, so it correctly has
        // neither — the system picker renders its own visual.
        let pairedControls: [RichTextControl] = [
            .bold, .italic, .underline, .strikethrough,
            .unorderedList, .orderedList, .heading(.h1), .heading(.h2), .heading(.h3),
        ]
        for control in pairedControls {
            let hasSymbol = control.systemImage != nil
            let hasText = control.textLabel != nil
            #expect(hasSymbol != hasText, "\(control) must have exactly one of symbol/text")
            #expect(control.accessibilityLabel.isEmpty == false)
        }

        #expect(RichTextControl.textColor.systemImage == nil)
        #expect(RichTextControl.textColor.textLabel == nil)
        #expect(RichTextControl.textColor.accessibilityLabel.isEmpty == false)
    }

    @Test func headingsAreDrawnAsText() {
        #expect(RichTextControl.heading(.h1).textLabel == "H1")
        #expect(RichTextControl.heading(.h3).textLabel == "H3")
        #expect(RichTextControl.heading(.h1).systemImage == nil)
    }

    @Test func accessibilityLabelsAreDistinct() {
        let controls: [RichTextControl] = [
            .bold, .italic, .underline, .strikethrough, .textColor,
            .unorderedList, .orderedList, .heading(.h1), .heading(.h2), .heading(.h3),
        ]
        let labels = Set(controls.map(\.accessibilityLabel))
        #expect(labels.count == controls.count)
    }
}
