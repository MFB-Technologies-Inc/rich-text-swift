// StaleListMarkerTests.swift
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

    /// UIKit lays out an edit before the engine syncs, so TextKit builds some
    /// fragments while the markers still describe the document as it was. It
    /// then reuses those fragments, and ones for untouched paragraphs further
    /// down, after the sync. Every fragment must still draw the right marker
    /// (GitHub issue #77).
    @MainActor
    struct StaleListMarkerTests {
        private let threeItems = "<ol><li>one</li><li>two</li><li>three</li></ol>"

        /// The markers each fragment draws, in document order, after `edit`
        /// has been laid out once before the sync and once after it.
        private func markersAfter(_ html: String, edit: (UITextView) -> Void) -> [String] {
            let textView = UITextView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
            let window = UIWindow(frame: textView.frame)
            window.addSubview(textView)
            window.makeKeyAndVisible()
            let engine = UIKitEditorEngine(textView: textView)
            engine.text = RichTextHTML.decode(html)
            textView.layoutIfNeeded()

            edit(textView)
            ensureLayout(textView)
            engine.synchronizeFromTextView()
            ensureLayout(textView)

            var markers: [String] = []
            if let layoutManager = textView.textLayoutManager,
               let range = layoutManager.textContentManager?.documentRange
            {
                layoutManager.enumerateTextLayoutFragments(from: range.location) { fragment in
                    if let fragment = fragment as? ListMarkerFragment {
                        markers += fragment.markerLayouts().map(\.text.string)
                    }
                    return true
                }
            }
            return markers
        }

        /// Lays out the whole document, the way UIKit does mid-edit.
        private func ensureLayout(_ textView: UITextView) {
            guard let layoutManager = textView.textLayoutManager,
                  let range = layoutManager.textContentManager?.documentRange
            else { return }
            layoutManager.ensureLayout(for: range)
            textView.layoutIfNeeded()
        }

        @Test func emptyingTheMiddleItemKeepsTheNextItemsMarker() {
            let markers = markersAfter(threeItems) { textView in
                textView.textStorage.replaceCharacters(in: NSRange(location: 4, length: 3), with: "")
            }
            #expect(markers == ["1.", "2.", "3."], "\(markers)")
        }

        @Test func typingInTheFirstItemKeepsTheMarkersBelowIt() {
            let markers = markersAfter(threeItems) { textView in
                textView.selectedRange = NSRange(location: 3, length: 0)
                textView.insertText("xy")
            }
            #expect(markers == ["1.", "2.", "3."], "\(markers)")
        }

        @Test func deletingAnItemRenumbersTheItemsBelowIt() {
            let markers = markersAfter("<ol><li>a</li><li>b</li><li>c</li><li>d</li></ol>") { textView in
                textView.textStorage.replaceCharacters(in: NSRange(location: 1, length: 2), with: "")
            }
            #expect(markers == ["1.", "2.", "3."], "\(markers)")
        }
    }
#endif
