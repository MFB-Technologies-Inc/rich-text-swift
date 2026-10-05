// EngineCoreDefaultColorNormalizationTests.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
import RichTextCore
@testable import RichTextEngine
import Testing

/// Covers `EngineCore.normalizingDefaultColor(_:)` — the single, structural
/// place that strips an explicit black `textColor` from a document, so that
/// no document held anywhere inside the engine can ever carry one, whatever
/// path it entered by (see `SemanticNSBridgeTests` and the UIKit engine
/// regression test for the two real ingest paths this closes).
struct EngineCoreDefaultColorNormalizationTests {
    private let red = RichTextColor(red: 255, green: 0, blue: 0)
    private let black = RichTextColor.black

    @Test func stripsAnExplicitBlackRun() {
        var doc = AttributedString("hi")
        doc.blockStyle = .paragraph
        doc.textColor = black

        let normalized = EngineCore.normalizingDefaultColor(doc)

        #expect(normalized.runs.first?.textColor == nil)
        #expect(String(normalized.characters) == "hi")
        #expect(normalized.runs.first?.blockStyle == .paragraph)
    }

    @Test func leavesANonBlackColorAlone() {
        var doc = AttributedString("hi")
        doc.blockStyle = .paragraph
        doc.textColor = red

        let normalized = EngineCore.normalizingDefaultColor(doc)

        #expect(normalized.runs.first?.textColor == red)
    }

    @Test func leavesAnUncoloredDocumentAlone() {
        let doc = Sem.block("hi")
        #expect(EngineCore.normalizingDefaultColor(doc) == doc)
    }

    @Test func stripsBlackFromOnlyTheAffectedRunsInAMultiRunDocument() {
        var doc = AttributedString("ab")
        doc.blockStyle = .paragraph
        let mid = doc.index(afterCharacter: doc.startIndex)
        doc[doc.startIndex ..< mid].textColor = black
        doc[mid ..< doc.endIndex].textColor = red

        let normalized = EngineCore.normalizingDefaultColor(doc)

        let colors: [RichTextColor?] = normalized.runs.map(\.textColor)
        #expect(colors == [nil, red])
    }
}
