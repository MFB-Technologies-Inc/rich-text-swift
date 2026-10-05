// ToolbarHostingTests.swift
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
    struct ToolbarHostingTests {
        /// Hosts a view in a real key window so SwiftUI actually lays it out.
        private func host(_ view: some View) -> UIWindow {
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
            window.rootViewController = UIHostingController(rootView: view)
            window.makeKeyAndVisible()
            window.layoutIfNeeded()
            return window
        }

        /// Finds the toolbar's horizontally-scrolling row. Its laid-out
        /// `contentSize` is a reliable, non-accessibility signal of how much the
        /// bar actually rendered: walking the hosted hierarchy's
        /// `UIView.subviews`/`accessibilityElements` (and even the legacy
        /// `UIAccessibilityContainer` index protocol) to find SwiftUI's
        /// accessibility labels turned up nothing at all here — not even for a
        /// fully populated bar — so that route isn't reliable and isn't used.
        ///
        /// Excludes `UITextView`, which is itself a `UIScrollView` subclass: any
        /// test that hosts the toolbar below a `RichTextEditor` (e.g. via
        /// `.richTextToolbar()`) would otherwise have this depth-first search
        /// match the editor's own text view before ever reaching the toolbar's
        /// row, since the editor sits earlier in the hierarchy.
        private func findScrollView(_ view: UIView) -> UIScrollView? {
            if let scrollView = view as? UIScrollView, !(scrollView is UITextView) {
                return scrollView
            }
            for sub in view.subviews {
                if let found = findScrollView(sub) {
                    return found
                }
            }
            return nil
        }

        private let allControls: [RichTextControl] = .html

        // Mirrors `RichTextToolbar`'s real layout: 44pt control frames, 4pt
        // `HStack` spacing between them, and 8pt padding on each horizontal
        // side — coupled to that view by construction, so if its spacing or
        // padding ever changes, this is the constant set that must follow.
        private static let controlFrameWidth: CGFloat = 44
        private static let interControlSpacing: CGFloat = 4
        private static let horizontalPadding: CGFloat = 8 * 2

        /// The content width `n` controls should produce under the layout above:
        /// `n*44 + (n-1)*4 + 16`.
        private func expectedContentWidth(forControlCount n: Int) -> CGFloat {
            CGFloat(n) * Self.controlFrameWidth
                + CGFloat(max(n - 1, 0)) * Self.interControlSpacing
                + Self.horizontalPadding
        }

        /// Headroom around an `expectedContentWidth` for SwiftUI's own rounding —
        /// kept well under half a control's width so a render that's missing or
        /// gaining even a single control still falls outside the tolerance.
        private static let layoutTolerance: CGFloat = 22

        /// A tightened lower bound for the full ten-control bar. Unlike the
        /// former `allControls.count * 44` (a bare product ignoring spacing and
        /// padding), this is derived from the real formula, so a bar rendering
        /// one control short of the full set no longer clears it.
        private var minimumFullBarContentWidth: CGFloat {
            expectedContentWidth(forControlCount: allControls.count) - Self.layoutTolerance
        }

        @Test func theBarLaysOutTheFullControlSet() async throws {
            let model = RichTextEditorModel()
            let window = host(RichTextToolbar(controls: allControls, model: model))
            await settle()
            window.layoutIfNeeded()
            // A laid-out bar has real height; a crashed or empty one does not.
            #expect(try #require(window.rootViewController?.view.bounds.height) > 0)
            #expect(window.rootViewController?.view.subviews.isEmpty == false)
            // Ten 44pt-tall controls give the scrolling row real content height —
            // the counterpart this test's assertion needs against the empty case
            // below (measured: ~52pt with padding, vs ~8pt of bare padding).
            let rootView = try #require(window.rootViewController?.view)
            let scrollView = try #require(findScrollView(rootView))
            #expect(scrollView.contentSize.height > 44)
            // Height alone would still pass with only some controls rendered;
            // width scales with the control count, so a partial render (e.g. 3 of
            // 10 controls) fails this even though it might pass the height check.
            #expect(scrollView.contentSize.width > minimumFullBarContentWidth)
        }

        @Test func anEmptyControlSetIsHarmless() async throws {
            let model = RichTextEditorModel()
            let window = host(RichTextToolbar(controls: [], model: model))
            await settle()
            window.layoutIfNeeded()
            // `subviews.isEmpty == false` alone only proves SwiftUI didn't crash:
            // the ScrollView/HStack chrome is present regardless of `controls`,
            // so that assertion passes vacuously even for a broken renderer. What
            // an empty control set actually implies is that the scrolling row
            // lays out with no meaningful content — just its own padding, not
            // 44pt-tall buttons — which the paired assertion in
            // `theBarLaysOutTheFullControlSet` shows the non-empty case violates.
            let rootView = try #require(window.rootViewController?.view)
            let scrollView = try #require(findScrollView(rootView))
            #expect(scrollView.contentSize.height < 44)
        }

        @Test func duplicateControlsDoNotCollide() async throws {
            // ForEach must not crash on repeated identities, and must actually lay
            // out all four controls (not silently collapse duplicates by value,
            // which `ForEach(_:id:)` keyed on content rather than position would).
            let model = RichTextEditorModel()
            let controls: [RichTextControl] = [.bold, .bold, .heading(.h1), .heading(.h1)]
            let window = host(RichTextToolbar(controls: controls, model: model))
            await settle()
            window.layoutIfNeeded()
            let rootView = try #require(window.rootViewController?.view)
            let scrollView = try #require(findScrollView(rootView))
            #expect(scrollView.contentSize.width > CGFloat(controls.count) * 44)
        }

        @Test func tappingAControlAppliesItsCommandThroughTheModel() {
            let model = RichTextEditorModel()
            let engine = FakeEditorEngine()
            model.attach(engine)
            let toolbar = RichTextToolbar(controls: allControls, model: model)

            toolbar.tap(.bold)
            toolbar.tap(.heading(.h2))
            toolbar.tap(.orderedList)

            #expect(engine.appliedCommands == [.toggleBold, .toggleHeading(2), .toggleList(.ordered)])
        }

        @Test func tappingTheColorControlSendsNothingByItself() {
            // The system picker's binding supplies the color directly; the bare
            // control has no command.
            let model = RichTextEditorModel()
            let engine = FakeEditorEngine()
            model.attach(engine)
            let toolbar = RichTextToolbar(controls: [.textColor], model: model)

            toolbar.tap(.textColor)

            #expect(engine.appliedCommands.isEmpty)
        }

        /// `onChange` may fire on an arbitrary executor, so the flag it sets has
        /// to be a `Sendable` box rather than a captured local var.
        private final class ChangeFlag: @unchecked Sendable {
            private let lock = NSLock()
            private var _fired = false
            var fired: Bool {
                get { lock.lock(); defer { lock.unlock() }; return _fired }
                set { lock.lock(); defer { lock.unlock() }; _fired = newValue }
            }
        }

        /// Proves that `RichTextToolbar`'s own read path — `isActive(_:)`, the one
        /// method `button(for:)` and `label(for:)` both call — registers an
        /// Observation dependency on `model.formatState`. That dependency is what
        /// would make the bar redraw when the model changes out from under it
        /// (carried-forward Task 3 review finding (a)).
        ///
        /// This does not prove SwiftUI actually re-renders pixels when the
        /// dependency fires — driving a real re-render isn't reachable from
        /// swift-testing here (see below) — only that the view's own code path
        /// reads `formatState` in a way Observation can track. Wrapping the
        /// expression at the call site (rather than re-typing it inline in the
        /// test) is what makes this fail if a future edit made `isActive(_:)`
        /// stop reading `formatState`, e.g. by caching a stale value or always
        /// returning a constant.
        ///
        /// A companion test asserting the *rendered* hierarchy's accessibility
        /// traits follow suit was attempted and dropped: walking the hosted
        /// `UIView` tree (`accessibilityElements` and the legacy
        /// `UIAccessibilityContainer` index protocol both) never turned up a
        /// single accessibility label anywhere in the hierarchy — not even for a
        /// fully populated bar — so there is no reliable route from a
        /// `UIHostingController`'s `UIView` tree to SwiftUI's accessibility tree
        /// here. This test plus a read of `RichTextToolbar.button(for:)` (which
        /// applies `.accessibilityAddTraits(isActive(control) ? [.isSelected] :
        /// [])`, and `TextColorControl` does the equivalent for `.textColor`) is
        /// the coverage we have for "the bar reflects selection state live".
        @Test func richTextToolbarWithNoArgumentsUsesTheDefaultPreset() async throws {
            let window = host(
                RichTextEditor(text: .constant(AttributedString("Hello")))
                    .richTextToolbar()
            )
            await settle()
            window.layoutIfNeeded()
            let rootView = try #require(window.rootViewController?.view)
            let scrollView = try #require(findScrollView(rootView))
            // Proves the no-argument form renders exactly the seven-control
            // `.default` set: the measured width is checked against the real
            // layout formula's prediction for seven controls (348pt), within a
            // tolerance far tighter than the 48pt gap to six controls (300pt) or
            // eight (396pt) — so this fails if the default preset ever gained or
            // lost a control, or became `.html` (492pt) outright.
            let expectedWidth = expectedContentWidth(forControlCount: [RichTextControl].default.count)
            #expect(abs(scrollView.contentSize.width - expectedWidth) < Self.layoutTolerance)
        }

        @Test func theViewsIsActiveReadPathRegistersAnObservationDependency() {
            let model = RichTextEditorModel()
            let engine = FakeEditorEngine()
            model.attach(engine)
            let toolbar = RichTextToolbar(controls: [.bold], model: model)

            let flag = ChangeFlag()
            withObservationTracking {
                _ = toolbar.isActive(.bold)
            } onChange: {
                flag.fired = true
            }

            // FakeEditorEngine.apply(_:) always sets formatState.bold = .on.
            model.apply(.toggleBold)

            #expect(flag.fired)
        }
    }
#endif
