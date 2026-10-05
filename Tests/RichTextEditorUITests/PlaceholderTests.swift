// PlaceholderTests.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
import RichTextCore
import Testing

#if os(iOS)
    @testable import RichTextEditorUI
    import SwiftUI
    import UIKit

    /// The placeholder is drawn as an overlay, never inserted into the document —
    /// placeholder text in the document would show up in `RichTextHTML.encode`
    /// output, shift every selection offset, and be deletable by the user.
    @MainActor
    struct PlaceholderTests {
        @Test func showsOnlyWhenThereIsAPlaceholderAndNoCharacters() {
            #expect(RichTextEditor.showsPlaceholder(placeholder: "Enter text here", in: AttributedString()))
            #expect(RichTextEditor.showsPlaceholder(placeholder: nil, in: AttributedString()) == false)
            #expect(RichTextEditor.showsPlaceholder(placeholder: "", in: AttributedString()) == false)
        }

        @Test func hidesAsSoonAsTheDocumentHasCharacters() {
            let typed = RichTextHTML.decode("<p>a</p>")
            #expect(RichTextEditor.showsPlaceholder(placeholder: "Enter text here", in: typed) == false)
        }

        @Test func aDocumentHoldingOnlyANewlineIsNotEmpty() {
            // Two empty blocks: there is something to type into, so no placeholder.
            var newlineOnly = AttributedString("\n")
            newlineOnly.blockStyle = .paragraph
            #expect(RichTextEditor.showsPlaceholder(placeholder: "Enter text here", in: newlineOnly) == false)
        }

        /// Turning a list on in an empty document starts the list, so the
        /// placeholder gives way to it (GitHub issue #71).
        @Test func hidesWhileTheCaretsBlockIsAListItem() {
            for style in [BlockStyle.listItem(.unordered, depth: 0), .listItem(.ordered, depth: 0)] {
                #expect(RichTextEditor.showsPlaceholder(
                    placeholder: "Enter text here",
                    in: AttributedString(),
                    blockStyle: style
                ) == false)
            }
        }

        @Test func showsAgainOnceTheListIsTurnedOff() {
            #expect(RichTextEditor.showsPlaceholder(
                placeholder: "Enter text here",
                in: AttributedString(),
                blockStyle: .paragraph
            ))
            #expect(RichTextEditor.showsPlaceholder(
                placeholder: "Enter text here",
                in: AttributedString(),
                blockStyle: nil
            ))
        }

        @Test func anEmptyDecodedDocumentStillCountsAsEmpty() {
            // What a consumer starting from empty HTML actually holds.
            #expect(RichTextEditor.showsPlaceholder(placeholder: "Enter text here", in: RichTextHTML.decode("")))
        }

        @Test func thePlaceholderNeverEntersTheDocument() async throws {
            var document = AttributedString()
            let binding = Binding<AttributedString>(get: { document }, set: { document = $0 })
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 400))
            window.rootViewController = UIHostingController(
                rootView: RichTextEditor(text: binding, placeholder: "Enter text here")
            )
            window.makeKeyAndVisible()
            window.layoutIfNeeded()
            await settle()
            window.layoutIfNeeded()

            #expect(document.characters.isEmpty)
            #expect(RichTextHTML.encode(document).contains("Enter text here") == false)

            func findTextView(_ view: UIView) -> UITextView? {
                if let textView = view as? UITextView {
                    return textView
                }
                for subview in view.subviews {
                    if let found = findTextView(subview) {
                        return found
                    }
                }
                return nil
            }
            #expect(try findTextView(#require(window.rootViewController?.view))?.textStorage.string.isEmpty == true)
        }

        @Test func theOverlayAlignsWithWhereTheTextViewDrawsItsFirstGlyph() {
            // The overlay's insets are taken from the text view's own values
            // rather than duplicated constants, so the two cannot drift.
            #expect(RichTextEditorRepresentable.textLeadingInset
                == RichTextEditorRepresentable.containerInset.left + RichTextEditorRepresentable.lineFragmentPadding)
            #expect(RichTextEditorRepresentable.textTopInset == RichTextEditorRepresentable.containerInset.top)
            #expect(RichTextEditorRepresentable.bodyFontSize == CGFloat(Theme.default.paragraph.fontSize))
        }
    }
#endif
