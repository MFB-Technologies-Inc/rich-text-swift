// CoordinatorRebindingNormalizationTests.swift
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

    /// A binding re-pointed by `updateUIView` while it still holds the raw
    /// document the coordinator adopted must still receive the line-ending
    /// write-back. Simulator-only.
    @MainActor
    struct CoordinatorRebindingNormalizationTests {
        private final class Box { var value = AttributedString(); var writeCount = 0 }

        private func binding(_ box: Box) -> Binding<AttributedString> {
            Binding(get: { box.value }, set: { box.value = $0; box.writeCount += 1 })
        }

        @Test func rebindingFromADroppingBindingWritesTheNormalizedDocumentToTheNewBinding() async {
            let raw = AttributedString("first\r\nsecond")
            let model = RichTextEditorModel()
            let coordinator = Coordinator(text: .constant(raw), model: model)
            let engine = UIKitEditorEngine(textView: UITextView())
            engine.text = raw
            coordinator.attach(engine: engine)
            model.attach(engine)
            await settle()

            let box = Box()
            box.value = raw
            coordinator.text = binding(box)
            coordinator.pushIfNeeded(box.value)
            await settle()
            #expect(String(box.value.characters) == "first\nsecond")
            #expect(box.writeCount == 1)
            #expect(coordinator.pushedDocumentCount == 0)
        }

        @Test func rebindingBeforeTheQueuedWriteBackRunsWritesToTheNewBindingToo() async {
            let raw = AttributedString("first\r\nsecond")
            let boxA = Box()
            boxA.value = raw
            let model = RichTextEditorModel()
            let coordinator = Coordinator(text: binding(boxA), model: model)
            let engine = UIKitEditorEngine(textView: UITextView())
            engine.text = raw
            coordinator.attach(engine: engine)
            model.attach(engine)

            let boxB = Box()
            boxB.value = raw
            coordinator.text = binding(boxB)
            coordinator.pushIfNeeded(boxB.value)
            await settle()
            #expect(String(boxB.value.characters) == "first\nsecond")
            #expect(boxB.writeCount == 1)
            #expect(boxA.value == raw)
            #expect(boxA.writeCount == 0)
        }

        @Test func bindingThatReturnsCRLFAfterEveryWriteStopsRetrying() async {
            let raw = AttributedString("first\r\nsecond")
            let box = Box()
            box.value = raw
            let binding = Binding<AttributedString>(
                get: { box.value },
                set: { _ in box.writeCount += 1 }
            )
            let coordinator = Coordinator(text: binding, model: RichTextEditorModel())
            let engine = UIKitEditorEngine(textView: UITextView())
            engine.text = raw
            coordinator.attach(engine: engine)
            for _ in 0 ..< 8 {
                await settle()
                coordinator.text = binding
                coordinator.pushIfNeeded(raw)
            }
            await settle()
            #expect(box.writeCount == 3)
            #expect(coordinator.pushedDocumentCount == 0)
        }

        @Test func aDifferentDocumentResetsTheWriteBackRetryLimit() async {
            let raw = AttributedString("first\r\nsecond")
            let other = AttributedString("different")
            let box = Box()
            box.value = raw
            let binding = Binding<AttributedString>(
                get: { box.value },
                set: { _ in box.writeCount += 1 }
            )
            let coordinator = Coordinator(text: binding, model: RichTextEditorModel())
            let engine = UIKitEditorEngine(textView: UITextView())
            engine.text = raw
            coordinator.attach(engine: engine)
            for _ in 0 ..< 4 {
                await settle()
                coordinator.pushIfNeeded(raw)
            }
            #expect(box.writeCount == 3)

            box.value = other
            coordinator.pushIfNeeded(other)
            box.value = raw
            coordinator.pushIfNeeded(raw)
            await settle()
            #expect(box.writeCount == 4)
        }

        @Test func aBindingThatRestylesOnReadAllowsALaterRawRevert() async {
            let raw = AttributedString("first\r\nsecond")
            let box = Box()
            box.value = raw
            let binding = Binding<AttributedString>(
                get: {
                    var read = box.value
                    if !read.unicodeScalars.contains("\r") {
                        read.italic = true
                    }
                    return read
                },
                set: { box.value = $0; box.writeCount += 1 }
            )
            let coordinator = Coordinator(text: binding, model: RichTextEditorModel())
            let engine = UIKitEditorEngine(textView: UITextView())
            engine.text = raw
            coordinator.attach(engine: engine)
            await settle()
            #expect(box.writeCount == 1)
            #expect(String(box.value.characters) == "first\nsecond")

            box.value = raw
            coordinator.pushIfNeeded(binding.wrappedValue)
            #expect(coordinator.pushedDocumentCount == 1)
        }
    }
#endif
