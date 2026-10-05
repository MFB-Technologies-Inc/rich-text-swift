// SimulatorLoopTests.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
import RichTextCore
@testable import RichTextEditorUI
import Testing

// Proves the simulator loop actually runs UIKit-dependent Swift Testing code
// (M4 decision D1). On macOS `canImport(UIKit)` is false, so this suite is
// compiled out entirely and `swift test` never sees it — exactly like the
// adapter source it exists to cover.
#if canImport(UIKit)
    import RichTextEngine
    import UIKit

    @MainActor
    struct SimulatorLoopTests {
        @Test func engineDrivesARealTextView() {
            let textView = UITextView()
            let engine = UIKitEditorEngine(textView: textView)
            engine.text = RichTextHTML.decode("<p>hello</p>")

            #expect(textView.textStorage.string == "hello")

            engine.selection = TextSelection(location: 0, length: 5)
            engine.apply(.toggleBold)

            #expect(RichTextHTML.encode(engine.text) == "<p><b>hello</b></p>")
            // The rendered storage really did pick up a bold font — this is the
            // adapter behavior no macOS test can reach.
            let font = textView.textStorage.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
            #expect(font?.fontDescriptor.symbolicTraits.contains(.traitBold) == true)
        }
    }
#endif
