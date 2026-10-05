// ListMarkerLayoutTests.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
import RichTextCore
import Testing

#if canImport(UIKit)
    @testable import RichTextEngine
    import UIKit

    /// Markers are drawn, never stored: the document must stay
    /// free of marker text while the view shows bullets and numbers.
    @MainActor
    struct ListMarkerLayoutTests {
        private func editor(_ html: String) -> (UITextView, UIKitEditorEngine) {
            let textView = UITextView()
            let engine = UIKitEditorEngine(textView: textView)
            engine.text = RichTextHTML.decode(html)
            return (textView, engine)
        }

        @Test func markerLookupFollowsTheBlockAnOffsetFallsIn() {
            let controller = ListMarkerLayoutController()
            controller.update(for: RichTextHTML.decode("<ol><li>one</li><li>two</li></ol><p>tail</p>"), theme: .default)
            // "one" occupies 0..<3, "two" 4..<7, "tail" 8..<12.
            #expect(controller.marker(atUTF16Offset: 0) == "1.")
            #expect(controller.marker(atUTF16Offset: 2) == "1.")
            #expect(controller.marker(atUTF16Offset: 4) == "2.")
            #expect(controller.marker(atUTF16Offset: 9) == nil)
        }

        @Test func markerLookupUpdatesWhenTheDocumentChanges() {
            let controller = ListMarkerLayoutController()
            controller.update(for: RichTextHTML.decode("<ul><li>one</li></ul>"), theme: .default)
            #expect(controller.marker(atUTF16Offset: 0) == "•")
            controller.update(for: RichTextHTML.decode("<ol><li>one</li></ol>"), theme: .default)
            #expect(controller.marker(atUTF16Offset: 0) == "1.")
        }

        @Test func markerLookupIsSafeOutsideTheDocument() {
            let controller = ListMarkerLayoutController()
            controller.update(for: RichTextHTML.decode("<p>hi</p>"), theme: .default)
            #expect(controller.marker(atUTF16Offset: 99) == nil)
            #expect(controller.marker(atUTF16Offset: -1) == nil)
        }

        @Test func theDocumentNeverContainsMarkerText() {
            let (textView, engine) = editor("<ol><li>one</li><li>two</li></ol>")
            #expect(textView.textStorage.string == "one\ntwo")
            #expect(RichTextHTML.encode(engine.text) == "<ol><li>one</li><li>two</li></ol>")
        }

        @Test func theEngineInstallsAMarkerFragmentForListBlocks() {
            let (textView, engine) = editor("<ul><li>one</li></ul>")
            // Force layout so fragments exist.
            textView.frame = CGRect(x: 0, y: 0, width: 320, height: 480)
            textView.layoutIfNeeded()
            let layoutManager = textView.textLayoutManager
            #expect(layoutManager?.delegate != nil)

            var sawMarkerFragment = false
            if let layoutManager, let range = layoutManager.textContentManager?.documentRange {
                layoutManager.enumerateTextLayoutFragments(from: range.location) { fragment in
                    if let markerFragment = fragment as? ListMarkerFragment, markerFragment.marker == "•" {
                        sawMarkerFragment = true
                    }
                    return true
                }
            }
            #expect(sawMarkerFragment)
            _ = engine
        }

        /// UIKit lays out an emptied document before the
        /// engine updates the markers, so the controller can still describe
        /// the deleted list item. The empty document's fragment must get no
        /// marker, or its bullet sits over the placeholder.
        @Test func anEmptyDocumentsFragmentGetsNoMarker() throws {
            let controller = ListMarkerLayoutController()
            controller.update(for: RichTextHTML.decode("<ul><li>one</li></ul>"), theme: .default)
            let layoutManager = NSTextLayoutManager()
            NSTextContentStorage().addTextLayoutManager(layoutManager)

            let fragment = try #require(controller.textLayoutManager(
                layoutManager,
                textLayoutFragmentFor: layoutManager.documentRange.location,
                in: NSTextParagraph(attributedString: NSAttributedString())
            ) as? ListMarkerFragment)

            #expect(fragment.blocks.isEmpty)
        }

        // MARK: - Fix 1: markers go stale on the typing path

        /// `synchronizeFromTextView()` never goes through `render(restoring:)`
        /// (typing/pasting already mutated `textStorage` directly), so nothing
        /// else recomputes `listMarkers` or invalidates the fragments caching the
        /// old offsets. Before the fix, this failed: `marker(atUTF16Offset: 9)`
        /// returned `nil` (the controller still only knew about a 3-character
        /// document) and `marker(atUTF16Offset: 2)` still read the pre-edit
        /// second item ("2.") instead of the first item's own marker.
        @Test func synchronizeFromTextViewRefreshesMarkersAgainstTheEditedDocument() {
            let textView = UITextView()
            let engine = UIKitEditorEngine(textView: textView)
            engine.text = RichTextHTML.decode("<ol><li>a</li><li>b</li></ol>")
            // "a" occupies 0..<1, "b" occupies 2..<3.
            textView.selectedRange = NSRange(location: 1, length: 0)
            textView.insertText("bcdefgh")
            // Document is now "abcdefgh\nb": item one is 0..<8, item two starts
            // at the new offset 9 — not its stale pre-edit offset of 2.
            engine.synchronizeFromTextView()

            #expect(engine.listMarkers.marker(atUTF16Offset: 9) == "2.")
            #expect(engine.listMarkers.marker(atUTF16Offset: 2) == "1.")
        }

        /// Fragment-level counterpart of the above: forcing a real layout pass
        /// after the edit must produce a fragment for the second item carrying
        /// the correct, post-edit marker — proving the invalidation half of the
        /// fix (not just the recomputed table) actually reaches TextKit.
        @Test func synchronizeFromTextViewInvalidatesLayoutSoTheNewMarkersAreDrawn() {
            let textView = UITextView()
            let engine = UIKitEditorEngine(textView: textView)
            engine.text = RichTextHTML.decode("<ol><li>a</li><li>b</li></ol>")
            textView.frame = CGRect(x: 0, y: 0, width: 320, height: 480)
            textView.layoutIfNeeded()

            textView.selectedRange = NSRange(location: 1, length: 0)
            textView.insertText("bcdefgh")
            engine.synchronizeFromTextView()
            textView.layoutIfNeeded()

            var sawUpdatedSecondItem = false
            if let layoutManager = textView.textLayoutManager,
               let range = layoutManager.textContentManager?.documentRange
            {
                layoutManager.enumerateTextLayoutFragments(from: range.location) { fragment in
                    if let markerFragment = fragment as? ListMarkerFragment, markerFragment.marker == "2." {
                        sawUpdatedSecondItem = true
                    }
                    return true
                }
            }
            #expect(sawUpdatedSecondItem)
        }

        // MARK: - Fix 3: vertical placement follows the first line, not the whole paragraph

        /// A three-line item at a 320pt width must still place its marker within
        /// the first line fragment's own bounds, not centered on the whole
        /// (multi-line) `layoutFragmentFrame`.
        @Test func markerStaysWithinTheFirstLineOfAWrappedItem() {
            let longText = Array(repeating: "wrap", count: 40).joined(separator: " ")
            let (textView, _) = editor("<ul><li>\(longText)</li></ul>")
            textView.frame = CGRect(x: 0, y: 0, width: 320, height: 480)
            textView.layoutIfNeeded()

            var checked = false
            if let layoutManager = textView.textLayoutManager,
               let range = layoutManager.textContentManager?.documentRange
            {
                layoutManager.enumerateTextLayoutFragments(from: range.location) { fragment in
                    guard let markerFragment = fragment as? ListMarkerFragment,
                          markerFragment.marker == "•" else { return true }
                    guard let firstLine = markerFragment.textLineFragments.first,
                          let (_, rect) = markerFragment.markerLayout()
                    else { return true }
                    #expect(markerFragment.textLineFragments.count > 1)
                    let firstLineBounds = firstLine.typographicBounds
                    let tolerance: CGFloat = 1
                    #expect(rect.minY >= firstLineBounds.minY - tolerance)
                    #expect(rect.maxY <= firstLineBounds.maxY + tolerance)
                    checked = true
                    return true
                }
            }
            #expect(checked)
        }

        // MARK: - Fix 4: a wide marker is not clamped into the text

        // MARK: - Regression: marker anchored to the text's leading edge, not an assumed origin

        //
        // The bug (screenshot: "fi•rst bullet" instead of "• first bullet"): the
        // marker's right edge must land `gap` points before where the text
        // *actually* starts — the first line fragment's own leading edge,
        // measured in the fragment-local space `markerLayout()` and
        // `draw(at:in:)` share — never re-derived from `indent` the way the
        // pre-fix formula (`indent - width - gap`) did. That formula assumed the
        // layout fragment's origin coincides with the text container's leading
        // edge; measurement showed it doesn't (the fragment already starts at
        // the head indent), so `indent` was counted twice and the marker was
        // pushed to the right of the text instead of into the gutter to its
        // left. These assertions would have caught that: against the pre-fix
        // code they fail because `rect.maxX` (computed from `indent`, which is
        // >0) lands to the right of `textLeadingEdge - gap` (0 - 6 = -6),
        // instead of at or before it.
        private func assertMarkerSitsBeforeTheText(
            _ markerFragment: ListMarkerFragment,
            sourceLocation: SourceLocation = #_sourceLocation
        ) {
            guard let firstLine = markerFragment.textLineFragments.first,
                  let (_, rect) = markerFragment.markerLayout()
            else {
                Issue.record("expected a line fragment and a marker layout to check", sourceLocation: sourceLocation)
                return
            }
            let textLeadingEdge = firstLine.typographicBounds.origin.x + firstLine.glyphOrigin.x
            let gap: CGFloat = 6
            let tolerance: CGFloat = 0.01
            #expect(rect.maxX <= textLeadingEdge - gap + tolerance, sourceLocation: sourceLocation)
        }

        @Test func aBulletedItemsMarkerSitsBeforeTheTextsLeadingEdge() {
            let (textView, _) = editor("<ul><li>first bullet</li></ul>")
            textView.frame = CGRect(x: 0, y: 0, width: 320, height: 480)
            textView.layoutIfNeeded()

            var checked = false
            if let layoutManager = textView.textLayoutManager,
               let range = layoutManager.textContentManager?.documentRange
            {
                layoutManager.enumerateTextLayoutFragments(from: range.location) { fragment in
                    guard let markerFragment = fragment as? ListMarkerFragment,
                          markerFragment.marker == "•" else { return true }
                    assertMarkerSitsBeforeTheText(markerFragment)
                    checked = true
                    return true
                }
            }
            #expect(checked)
        }

        /// Depth 2 (the item nested two levels deep) has both a wider gutter and
        /// a different glyph ("▪") — the relationship must hold there too, not
        /// just at depth 0.
        @Test func aNestedItemAtDepthTwoMarkerSitsBeforeTheTextsLeadingEdge() {
            let (textView, _) = editor("<ul><li>top<ul><li>mid<ul><li>deep</li></ul></li></ul></li></ul>")
            textView.frame = CGRect(x: 0, y: 0, width: 320, height: 480)
            textView.layoutIfNeeded()

            var checked = false
            if let layoutManager = textView.textLayoutManager,
               let range = layoutManager.textContentManager?.documentRange
            {
                layoutManager.enumerateTextLayoutFragments(from: range.location) { fragment in
                    guard let markerFragment = fragment as? ListMarkerFragment,
                          markerFragment.indent == 72 else { return true }
                    assertMarkerSitsBeforeTheText(markerFragment)
                    checked = true
                    return true
                }
            }
            #expect(checked)
        }

        /// A 10+ item ordered list produces a "12." marker wide enough to
        /// overflow a single-level gutter — exactly the case Fix 4 preserved
        /// (no clamping), and exactly the case the double-counted-indent bug
        /// pushed into the text instead of further left.
        @Test func anOrderedItemPastTenHasAWideMarkerThatStillSitsBeforeTheText() {
            let items = (1 ... 12).map { "<li>item\($0)</li>" }.joined()
            let (textView, _) = editor("<ol>\(items)</ol>")
            textView.frame = CGRect(x: 0, y: 0, width: 320, height: 480)
            textView.layoutIfNeeded()

            var checked = false
            if let layoutManager = textView.textLayoutManager,
               let range = layoutManager.textContentManager?.documentRange
            {
                layoutManager.enumerateTextLayoutFragments(from: range.location) { fragment in
                    guard let markerFragment = fragment as? ListMarkerFragment,
                          markerFragment.marker == "12." else { return true }
                    assertMarkerSitsBeforeTheText(markerFragment)
                    checked = true
                    return true
                }
            }
            #expect(checked)
        }

        // MARK: - Fix 5: marker font/color follow the block's own resolved style

        @Test func markerFontAndColorFollowTheBlocksOwnResolvedStyleAndTheme() {
            var theme = Theme.default
            theme.listItem = Theme.BlockAttributes(
                fontSize: 30,
                foregroundColor: RichTextColor(red: 10, green: 20, blue: 30)
            )
            let textView = UITextView()
            let engine = UIKitEditorEngine(textView: textView, theme: theme)
            engine.text = RichTextHTML.decode("<ul><li>one</li></ul>")
            textView.frame = CGRect(x: 0, y: 0, width: 320, height: 480)
            textView.layoutIfNeeded()

            var font: UIFont?
            var color: UIColor?
            if let layoutManager = textView.textLayoutManager,
               let range = layoutManager.textContentManager?.documentRange
            {
                layoutManager.enumerateTextLayoutFragments(from: range.location) { fragment in
                    if let markerFragment = fragment as? ListMarkerFragment, markerFragment.marker == "•" {
                        font = markerFragment.markerAttributes[.font] as? UIFont
                        color = markerFragment.markerAttributes[.foregroundColor] as? UIColor
                    }
                    return true
                }
            }
            #expect(font?.pointSize == 30)
            #expect(color == UIKitRendering.uiColor(RichTextColor(red: 10, green: 20, blue: 30)))
        }

        // MARK: - Pending-role rendering fix: the next marker shows immediately after Return

        /// The pinned bug: pressing Return at the end of a list item must show
        /// the next bullet/number on the new, still-empty line immediately —
        /// not only once a character is typed. Before the fix, the marker
        /// controller reports `nil` for the new empty block's offset because
        /// `BlockScanner.blocks(of:)` reports `.paragraph` for it (Foundation
        /// cannot attribute zero-length content); the actual role only lives in
        /// `typingAttributes.blockStyle`, which nothing fed to
        /// the renderer before this fix.
        @Test func theNextMarkerAppearsImmediatelyAfterReturn() {
            let (_, engine) = editor("<ol><li>one</li></ol>")
            // Caret at the end of "one" (offset 3).
            engine.selection = TextSelection(location: 3, length: 0)

            engine.insertNewline()

            // The new empty block starts right after "one\n" — offset 4.
            #expect(engine.listMarkers.marker(atUTF16Offset: 4) == "2.")
        }

        /// Pressing Return a second time on that now-empty item leaves the list
        /// (already-working behavior) — the marker must disappear along with it.
        @Test func aSecondReturnLeavesTheListAndClearsTheMarker() {
            let (_, engine) = editor("<ol><li>one</li></ol>")
            engine.selection = TextSelection(location: 3, length: 0)
            engine.insertNewline()

            engine.insertNewline()

            #expect(engine.listMarkers.marker(atUTF16Offset: 4) == nil)
        }

        // MARK: - Fix 7: untested behaviors

        @Test func aParagraphBlockGetsNoMarkerInARealLayoutPass() {
            let (textView, _) = editor("<p>plain text</p>")
            textView.frame = CGRect(x: 0, y: 0, width: 320, height: 480)
            textView.layoutIfNeeded()

            var sawAFragment = false
            if let layoutManager = textView.textLayoutManager,
               let range = layoutManager.textContentManager?.documentRange
            {
                layoutManager.enumerateTextLayoutFragments(from: range.location) { fragment in
                    if let markerFragment = fragment as? ListMarkerFragment {
                        sawAFragment = true
                        #expect(markerFragment.marker == nil)
                    }
                    return true
                }
            }
            #expect(sawAFragment)
        }

        // MARK: - The trailing case: Return at the very end of the document

        //
        // TextKit does not create a separate layout fragment for the
        // document-final empty block — measured: for "first item\n" it places
        // that empty line as a *second* `NSTextLineFragment` inside the *same*
        // fragment as "first item", rather than giving it a fragment of its own.
        // A `ListMarkerFragment` that only ever draws one marker, anchored to its
        // first line, therefore never shows "2." on that trailing empty line —
        // the bug the user actually reported. This must draw a marker on every
        // line that begins a block, not just the fragment's first.

        @Test func aTrailingReturnDrawsMarkersOnBothLinesOfTheOneFragmentTextKitGives() {
            let (textView, engine) = editor("<ol><li>first item</li></ol>")
            textView.frame = CGRect(x: 0, y: 0, width: 320, height: 480)
            textView.layoutIfNeeded()

            engine.selection = TextSelection(location: 10, length: 0)
            engine.insertNewline()
            textView.layoutIfNeeded()

            var fragmentsWithMultipleLines: [ListMarkerFragment] = []
            var allMarkersSeen: [String?] = []
            if let layoutManager = textView.textLayoutManager,
               let range = layoutManager.textContentManager?.documentRange
            {
                layoutManager.enumerateTextLayoutFragments(from: range.location) { fragment in
                    if let markerFragment = fragment as? ListMarkerFragment {
                        allMarkersSeen.append(markerFragment.marker)
                        if markerFragment.textLineFragments.count > 1 {
                            fragmentsWithMultipleLines.append(markerFragment)
                        }
                    }
                    return true
                }
            }
            print("TRAILING-CASE markers across all fragments == \(allMarkersSeen)")

            #expect(fragmentsWithMultipleLines.count == 1)
            let fragment = fragmentsWithMultipleLines.first
            print("TRAILING-CASE lineMarkers == \(String(describing: fragment?.lineMarkers.mapValues(\.text)))")
            #expect(fragment?.lineMarkers[0]?.text == "1.")
            #expect(fragment?.lineMarkers[1]?.text == "2.")
        }

        /// A nested list item (depth 1) must resolve both the depth-appropriate
        /// bullet glyph and the depth-appropriate indent through the controller
        /// — not depth 0's, which is all a real layout pass exercised before.
        @Test func aNestedListItemResolvesItsOwnGlyphAndIndentThroughTheController() {
            let (textView, _) = editor("<ul><li>top<ul><li>nested</li></ul></li></ul>")
            textView.frame = CGRect(x: 0, y: 0, width: 320, height: 480)
            textView.layoutIfNeeded()

            var sawNestedFragment = false
            if let layoutManager = textView.textLayoutManager,
               let range = layoutManager.textContentManager?.documentRange
            {
                layoutManager.enumerateTextLayoutFragments(from: range.location) { fragment in
                    if let markerFragment = fragment as? ListMarkerFragment, markerFragment.marker == "◦" {
                        sawNestedFragment = true
                        // depth 1 -> indentLevel 2 -> 2 * Theme.default.listIndent (24).
                        #expect(markerFragment.indent == 48)
                    }
                    return true
                }
            }
            #expect(sawNestedFragment)
        }
    }
#endif
