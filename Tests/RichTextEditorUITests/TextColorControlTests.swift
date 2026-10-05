// TextColorControlTests.swift
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
    struct TextColorControlTests {
        /// A few arbitrary non-black colors. Black is deliberately absent: it now
        /// means "no color", so it is not a useful case for "each selection reaches
        /// the model".
        private static let sampleColors = [
            RichTextColor(red: 255, green: 59, blue: 48),
            RichTextColor(red: 0, green: 122, blue: 255),
            RichTextColor(red: 52, green: 199, blue: 89),
        ]

        private func attached() -> (RichTextEditorModel, FakeEditorEngine) {
            let model = RichTextEditorModel()
            let engine = FakeEditorEngine()
            model.attach(engine)
            return (model, engine)
        }

        @Test func selectingAColorAppliesThatExactColor() {
            let (model, engine) = attached()
            let menu = TextColorControl(model: model, isActive: false)
            let red = RichTextColor(red: 255, green: 59, blue: 48)

            menu.select(red)

            #expect(engine.appliedCommands == [.setTextColor(red)])
        }

        @Test func everySelectionReachesTheModel() {
            let (model, engine) = attached()
            let menu = TextColorControl(model: model, isActive: false)

            for color in Self.sampleColors {
                menu.select(color)
            }

            #expect(engine.appliedCommands == Self.sampleColors.map { .setTextColor($0) })
        }

        // Note (Important 3): a `theControlRendersAtTheChromeSize` test used to
        // live here, asserting `ImageRenderer`'s output was 44x44. It claimed
        // `toolbarControlChrome` fixed the size, but `TextColorControl` never used
        // that modifier — it hardcodes `.frame(width: 44, height: 44)` — and
        // `ImageRenderer` draws a `ColorPicker` as SwiftUI's unsupported-view
        // placeholder, so the assertion passed for a blank 44x44 box regardless
        // of what the control actually laid out. Deleted rather than fixed: it is
        // fully subsumed by `TextColorControlRenderingTests.theControlLaysOutWithinTheToolbarChrome`
        // in `TextColorControlRenderingTests.swift`, which hosts the view in a
        // real `UIWindow` and measures the actual `UIColorWell`'s bounds — a
        // strictly stronger version of the same claim.

        // MARK: - `selection` binding (Important 1 / Important 2)

        //
        // `selection` backs the `ColorPicker` and is where the drag guard and the
        // "no color -> shows black" fallback both live. It was `private`, so
        // nothing could exercise it directly; widened to internal (see its doc
        // comment) purely so these tests can reach it without a hosted view
        // hierarchy.

        private func attachedWithColor(_ color: RichTextColor?) async -> (RichTextEditorModel, FakeEditorEngine) {
            let model = RichTextEditorModel()
            let engine = FakeEditorEngine()
            engine.formatState.textColor = color
            model.attach(engine)
            await settle()
            return (model, engine)
        }

        @Test func selectionGetterReflectsFormatState() async {
            let red = RichTextColor(red: 255, green: 59, blue: 48)
            let (model, _) = await attachedWithColor(red)
            let menu = TextColorControl(model: model, isActive: false)

            #expect(menu.selection.wrappedValue == Color(red))
        }

        @Test func selectionGetterFallsBackToBlackWhenThereIsNoColor() async {
            let (model, _) = await attachedWithColor(nil)
            let menu = TextColorControl(model: model, isActive: false)

            #expect(menu.selection.wrappedValue == Color(RichTextColor.black))
        }

        @Test func selectionSetterIssuesNoCommandWhenTheResolvedColorEqualsTheCurrentOne() async {
            let red = RichTextColor(red: 255, green: 59, blue: 48)
            let (model, engine) = await attachedWithColor(red)
            let menu = TextColorControl(model: model, isActive: false)

            // The picker fires continuously while dragging; picking the exact
            // color already applied must be a no-op (the drag guard), not a
            // redundant `.setTextColor` command.
            menu.selection.wrappedValue = Color(red)

            #expect(engine.appliedCommands.isEmpty)
        }

        @Test func selectionSetterIssuesACommandWhenTheResolvedColorDiffers() async {
            let red = RichTextColor(red: 255, green: 59, blue: 48)
            let blue = RichTextColor(red: 0, green: 122, blue: 255)
            let (model, engine) = await attachedWithColor(red)
            let menu = TextColorControl(model: model, isActive: false)

            menu.selection.wrappedValue = Color(blue)

            #expect(engine.appliedCommands == [.setTextColor(blue)])
        }

        // MARK: - `RichTextColor(_ resolved: Color.Resolved)` (Important 2)

        //
        // The sRGB narrowing with clamping and rounding this change introduced,
        // exercised directly against `Color.Resolved` rather than through a
        // picker gesture.

        @Test func resolvedColorConversionRoundsToNearestByte() {
            let resolved = Color.Resolved(red: 1.0, green: 0.0, blue: 0.5019608, opacity: 1)
            #expect(RichTextColor(resolved) == RichTextColor(red: 255, green: 0, blue: 128))
        }

        @Test func resolvedColorConversionClampsComponentsBelowZero() {
            let resolved = Color.Resolved(red: -0.5, green: 0.5, blue: -1, opacity: 1)
            #expect(RichTextColor(resolved) == RichTextColor(red: 0, green: 128, blue: 0))
        }

        @Test func resolvedColorConversionClampsComponentsAboveOne() {
            let resolved = Color.Resolved(red: 1.5, green: 1.0, blue: 2.0, opacity: 1)
            #expect(RichTextColor(resolved) == RichTextColor(red: 255, green: 255, blue: 255))
        }

        @Test func resolvedColorConversionRoundsAtTheHalfBoundary() {
            // 0.5 * 255 = 127.5, which `.rounded()` (toNearestOrAwayFromZero)
            // takes to 128, not 127.
            let resolved = Color.Resolved(red: 0.5, green: 0, blue: 0, opacity: 1)
            #expect(RichTextColor(resolved).red == 128)
        }
    }
#endif
