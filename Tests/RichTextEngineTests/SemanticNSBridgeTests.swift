// SemanticNSBridgeTests.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
import RichTextCore
@testable import RichTextEngine
import Testing

struct SemanticNSBridgeTests {
    private let red = RichTextColor(red: 255, green: 0, blue: 0)

    private func roundTrip(_ text: AttributedString) -> AttributedString {
        SemanticNSBridge.attributedString(from: SemanticNSBridge.nsAttributedString(from: text))
    }

    // MARK: - Round trip

    @Test func plainSingleBlockText() {
        let doc = Sem.block("Hello world")
        #expect(roundTrip(doc) == doc)
    }

    @Test func aHeading() {
        let doc = Sem.block("Title", .heading(2))
        #expect(roundTrip(doc) == doc)
    }

    @Test func twoParagraphs() {
        let doc = Sem.doc(Sem.block("First"), Sem.block("Second"))
        #expect(roundTrip(doc) == doc)
    }

    @Test func headingFollowedByParagraph() {
        let doc = Sem.doc(Sem.block("Title", .heading(1)), Sem.block("Body"))
        #expect(roundTrip(doc) == doc)
    }

    @Test func nestedListItemsAtDifferentDepthsAndKinds() {
        let doc = Sem.doc(
            Sem.block("One", .listItem(.unordered, depth: 0)),
            Sem.block("Two", .listItem(.unordered, depth: 1)),
            Sem.block("Three", .listItem(.ordered, depth: 2))
        )
        #expect(roundTrip(doc) == doc)
    }

    @Test func severalMixedInlineRunsInOneBlock() {
        var doc = Sem.block("abcdefghi")
        doc[TextOffsets.range(TextSelection(location: 0, length: 3), in: doc)].bold = true
        doc[TextOffsets.range(TextSelection(location: 3, length: 3), in: doc)].italic = true
        doc[TextOffsets.range(TextSelection(location: 6, length: 3), in: doc)].underline = true
        #expect(roundTrip(doc) == doc)
    }

    @Test func aTextColor() {
        let doc = Sem.with(Sem.block("colored"), color: red)
        #expect(roundTrip(doc) == doc)
    }

    /// Blocker 1's storage read-back path: an `NSAttributedString` can carry
    /// an explicit black `textColorKey` attribute — e.g. a text view a
    /// consumer pre-populated before ever going through the command layer —
    /// and `attributedString(from:)` must normalize it away rather than
    /// faithfully reproducing it, so no document read out of storage can ever
    /// carry black (`RichTextColor.black` is the absence of a color
    /// everywhere in the system).
    @Test func readingBackAnExplicitBlackRunFromStorageStripsIt() {
        let ns = NSMutableAttributedString(string: "hi")
        ns.addAttribute(
            SemanticNSBridge.blockStyleKey,
            value: BlockStyle.paragraph,
            range: NSRange(location: 0, length: 2)
        )
        ns.addAttribute(
            SemanticNSBridge.textColorKey,
            value: RichTextColor.black,
            range: NSRange(location: 0, length: 2)
        )

        let decoded = SemanticNSBridge.attributedString(from: ns)

        #expect(decoded.runs.first?.textColor == nil)
        #expect(RichTextHTML.encode(decoded) == "<p>hi</p>")
    }

    // MARK: - Pending-role rendering safety (rendering counterpart of D13)

    /// What a real `UITextView` would produce while a pending list-item role
    /// (D13) is active: `pushTypingAttributes()` stamps `blockStyle` onto the
    /// text view's typing attributes, and UIKit applies those to every
    /// inserted character — including a bare "\n" that forms an empty
    /// paragraph entirely on its own. This proves `attributedString(from:)`
    /// already strips that pollution back off (via `formsEmptyBlock`), so
    /// *rendering* the pending role for the Return-key fix can never leak it
    /// into the model, and the document still round-trips through HTML.
    @Test func aPendingRoleStampedOnAnEmptyBlocksOwnNewlineNeverReachesTheModel() {
        let storage = NSMutableAttributedString(string: "one\n\n")
        // "one\n" — block 0's own, legitimate style.
        storage.addAttribute(
            SemanticNSBridge.blockStyleKey,
            value: BlockStyle.listItem(.ordered, depth: 0),
            range: NSRange(location: 0, length: 4)
        )
        // The second "\n" forms an empty paragraph entirely on its own (it is
        // immediately preceded by another newline) — exactly the shape of an
        // empty list item's terminator — yet carries the same style, as a
        // real text view's typing attributes would stamp onto it.
        storage.addAttribute(
            SemanticNSBridge.blockStyleKey,
            value: BlockStyle.listItem(.ordered, depth: 0),
            range: NSRange(location: 4, length: 1)
        )

        let model = SemanticNSBridge.attributedString(from: storage)
        let emptyBlock = BlockScanner.blocks(of: model)[1]
        #expect(emptyBlock.isEmpty)
        #expect(emptyBlock.style == .paragraph)

        let html = RichTextHTML.encode(model)
        #expect(RichTextHTML.decode(html) == model)
    }

    @Test func documentWithAnEmptyBlockInTheMiddle() {
        let doc = Sem.doc(Sem.block("First"), Sem.block(""), Sem.block("Last"))
        #expect(roundTrip(doc) == doc)
    }

    @Test func documentWithATrailingNewline() {
        let doc = Sem.doc(Sem.block("First"), Sem.block(""))
        #expect(roundTrip(doc) == doc)
    }

    @Test func emptyDocument() {
        let doc = AttributedString("")
        #expect(roundTrip(doc) == doc)
    }

    // MARK: - Separator invariant

    @Test func separatorCharactersCarryNoInlineAttributesInTheProducedNSAttributedString() {
        let doc = Sem.doc(
            Sem.with(Sem.block("abc", .heading(1)), bold: true, color: red),
            Sem.with(Sem.block("def"), italic: true)
        )
        let ns = SemanticNSBridge.nsAttributedString(from: doc)
        // "abc\ndef" -> the separator is at index 3. These fixtures force the
        // separator into its own run (inline attributes differ on either
        // side), so this only tests the no-inline-attributes half of the
        // invariant. See `separatorOnAnUnsplitTwoBlockDocumentCarriesOnlyBlockStyle`
        // below for the un-split shape, where `blockStyle` normalization is
        // actually observable.
        let separatorRange = NSRange(location: 3, length: 1)
        let attributes = ns.attributes(at: 3, effectiveRange: nil)
        #expect(attributes[SemanticNSBridge.boldKey] == nil)
        #expect(attributes[SemanticNSBridge.italicKey] == nil)
        #expect(attributes[SemanticNSBridge.underlineKey] == nil)
        #expect(attributes[SemanticNSBridge.strikethroughKey] == nil)
        #expect(attributes[SemanticNSBridge.textColorKey] == nil)
        #expect((ns.string as NSString).substring(with: separatorRange) == "\n")
    }

    /// Documents the *actual* observed attribute layout on a block separator
    /// when there is no inline attribute forcing it into its own run: a plain
    /// two-block document with no bold/italic/underline/strikethrough/color
    /// anywhere. `BlockStyleKey` declares `runBoundaries: .paragraph`, so
    /// Foundation normalizes it across each paragraph including its
    /// terminating newline — the separator ends up carrying the *preceding*
    /// block's `blockStyle`, not "no attributes at all".
    @Test func separatorOnAnUnsplitTwoBlockDocumentCarriesOnlyBlockStyle() {
        let doc = Sem.doc(Sem.block("abc", .heading(1)), Sem.block("def"))
        let ns = SemanticNSBridge.nsAttributedString(from: doc)
        // "abc\ndef" -> the separator is at index 3.
        let attributes = ns.attributes(at: 3, effectiveRange: nil)
        #expect(attributes[SemanticNSBridge.blockStyleKey] as? BlockStyle == .heading(1))
        #expect(attributes[SemanticNSBridge.boldKey] == nil)
        #expect(attributes[SemanticNSBridge.italicKey] == nil)
        #expect(attributes[SemanticNSBridge.underlineKey] == nil)
        #expect(attributes[SemanticNSBridge.strikethroughKey] == nil)
        #expect(attributes[SemanticNSBridge.textColorKey] == nil)
        #expect((ns.string as NSString).substring(with: NSRange(location: 3, length: 1)) == "\n")
    }

    /// The other half of the picture: when the block *does* carry an inline
    /// attribute up to its terminating newline, that difference forces the
    /// newline into a run of its own, and the write path's `runString == "\n"`
    /// branch appends *any* lone separator run with a completely empty
    /// attribute dictionary — `blockStyle` included, not just the inline
    /// flags. This is the case
    /// `separatorCharactersCarryNoInlineAttributesInTheProducedNSAttributedString`
    /// above only partially covers (it asserts the inline keys are absent but
    /// not that `blockStyle` is too). Round-tripping still holds regardless
    /// (the read path re-derives `blockStyle` from paragraph boundaries in the
    /// raw string, not from what's on the newline) — see
    /// `roundTrippedDocumentEncodesToTheSameHTMLAsTheOriginal` below, which
    /// uses this exact document.
    @Test func separatorIsCompletelyBareWhenSplitIntoItsOwnRunByAnInlineAttribute() {
        let doc = Sem.doc(
            Sem.with(Sem.block("Title", .heading(1)), bold: true),
            Sem.block("Body")
        )
        let ns = SemanticNSBridge.nsAttributedString(from: doc)
        // "Title\nBody" -> the separator is at index 5.
        let attributes = ns.attributes(at: 5, effectiveRange: nil)
        #expect(attributes.isEmpty)
        #expect((ns.string as NSString).substring(with: NSRange(location: 5, length: 1)) == "\n")
    }

    // MARK: - Pollution on the read path (Fix 1)

    //
    // A real UIKit text view applies its typing attributes to every inserted
    // character, including a typed "\n": type "abc", select it, tap Bold, put
    // the caret at the end, press Return -> storage holds "abc"{bold} +
    // "\n"{bold}. These tests simulate that by taking a *healthy* encoded
    // document and then polluting it exactly the way a text view would —
    // stamping an inline attribute across the whole range, which merges the
    // separator into one run with its neighboring text — and checking the
    // read path (`attributedString(from:)`) still produces a canonical model.

    /// True if any run touching a newline character carries an inline
    /// (non-blockStyle) attribute.
    private func newlineRunsCarryInlineAttributes(_ text: AttributedString) -> Bool {
        for run in text.runs {
            let slice = text[run.range]
            guard String(slice.characters).contains("\n") else { continue }
            if slice.bold == true || slice.italic == true || slice.underline == true
                || slice.strikethrough == true || slice.textColor != nil
            {
                return true
            }
        }
        return false
    }

    @Test func boldSpanningTextAndANewlineInOneRunDropsBoldFromTheNewline() {
        let canonical = Sem.doc(
            Sem.with(Sem.block("abc"), bold: true),
            Sem.with(Sem.block("def"), bold: true)
        )
        let ns = NSMutableAttributedString(attributedString: SemanticNSBridge.nsAttributedString(from: canonical))
        // Pollute: stamp bold across the entire "abc\ndef" range in one call,
        // merging the previously-separate separator run into its neighbors.
        ns.addAttribute(SemanticNSBridge.boldKey, value: true, range: NSRange(location: 0, length: ns.length))

        let decoded = SemanticNSBridge.attributedString(from: ns)
        #expect(!newlineRunsCarryInlineAttributes(decoded))
        #expect(decoded == canonical)
        #expect(RichTextHTML.decode(RichTextHTML.encode(decoded)) == decoded)
    }

    @Test func textColorSpanningTextAndANewlineInOneRunDropsColorFromTheNewline() {
        let canonical = Sem.doc(
            Sem.with(Sem.block("abc"), color: red),
            Sem.with(Sem.block("def"), color: red)
        )
        let ns = NSMutableAttributedString(attributedString: SemanticNSBridge.nsAttributedString(from: canonical))
        ns.addAttribute(SemanticNSBridge.textColorKey, value: red, range: NSRange(location: 0, length: ns.length))

        let decoded = SemanticNSBridge.attributedString(from: ns)
        #expect(!newlineRunsCarryInlineAttributes(decoded))
        #expect(decoded == canonical)
        #expect(RichTextHTML.decode(RichTextHTML.encode(decoded)) == decoded)
    }

    @Test func consecutiveNewlinesDoNotPickUpPollutedBold() {
        let canonical = Sem.doc(
            Sem.with(Sem.block("abc"), bold: true),
            Sem.block(""),
            Sem.with(Sem.block("def"), bold: true)
        )
        // "abc" + "\n" + "" + "\n" + "def" -> "abc\n\ndef", two newlines in a row.
        #expect(String(canonical.characters) == "abc\n\ndef")
        let ns = NSMutableAttributedString(attributedString: SemanticNSBridge.nsAttributedString(from: canonical))
        ns.addAttribute(SemanticNSBridge.boldKey, value: true, range: NSRange(location: 0, length: ns.length))

        let decoded = SemanticNSBridge.attributedString(from: ns)
        #expect(!newlineRunsCarryInlineAttributes(decoded))
        #expect(decoded == canonical)
        #expect(RichTextHTML.decode(RichTextHTML.encode(decoded)) == decoded)
    }

    @Test func newlineAtTheVeryStartDoesNotPickUpPollutedBold() {
        let canonical = Sem.doc(Sem.block(""), Sem.with(Sem.block("abc"), bold: true))
        #expect(String(canonical.characters) == "\nabc")
        let ns = NSMutableAttributedString(attributedString: SemanticNSBridge.nsAttributedString(from: canonical))
        ns.addAttribute(SemanticNSBridge.boldKey, value: true, range: NSRange(location: 0, length: ns.length))

        let decoded = SemanticNSBridge.attributedString(from: ns)
        #expect(!newlineRunsCarryInlineAttributes(decoded))
        #expect(decoded == canonical)
        #expect(RichTextHTML.decode(RichTextHTML.encode(decoded)) == decoded)
    }

    @Test func newlineAtTheVeryEndDoesNotPickUpPollutedBold() {
        let canonical = Sem.doc(Sem.with(Sem.block("abc"), bold: true), Sem.block(""))
        #expect(String(canonical.characters) == "abc\n")
        let ns = NSMutableAttributedString(attributedString: SemanticNSBridge.nsAttributedString(from: canonical))
        ns.addAttribute(SemanticNSBridge.boldKey, value: true, range: NSRange(location: 0, length: ns.length))

        let decoded = SemanticNSBridge.attributedString(from: ns)
        #expect(!newlineRunsCarryInlineAttributes(decoded))
        #expect(decoded == canonical)
        #expect(RichTextHTML.decode(RichTextHTML.encode(decoded)) == decoded)
    }

    // MARK: - An empty block's own newline must come back bare (Fix 1)

    //
    // `blockStyle` declares `runBoundaries: .paragraph`, so it legitimately
    // rides on the newline that *terminates* a non-empty block (covered
    // above). But a newline that *constitutes its own empty paragraph* — at
    // the very start of the document, or immediately after another newline —
    // must come back bare, because `RichTextHTML.decode` leaves such a
    // newline with no attributes at all (an empty block can't hold a custom
    // attribute on zero characters). A real text view stamps its typing
    // attributes onto every typed character, including a typed "\n", so these
    // tests build the `NSAttributedString` a text view would actually produce
    // — with `blockStyle` stamped straight across an empty block's
    // newline — and confirm the read path strips it back off.

    @Test func pressingReturnTwiceLeavesTheEmptyBlocksNewlineBare() {
        // "abc\n\ndef": user types "abc", presses Return twice (both
        // newlines inherit the .paragraph typing attribute), then "def".
        let ns = NSMutableAttributedString(string: "abc\n\ndef")
        ns.addAttribute(
            SemanticNSBridge.blockStyleKey,
            value: BlockStyle.paragraph,
            range: NSRange(location: 0, length: ns.length)
        )

        let decoded = SemanticNSBridge.attributedString(from: ns)
        let canonical = Sem.doc(Sem.block("abc"), Sem.block(""), Sem.block("def"))
        #expect(decoded == canonical)
        #expect(RichTextHTML.decode(RichTextHTML.encode(decoded)) == decoded)
    }

    @Test func headingBeforeAnEmptyBlockLeavesItsNewlineBare() {
        // "Title"{h1} + "\n"{h1} + "\n"{paragraph} + "body"{paragraph}: the
        // heading's own terminating newline legitimately keeps .heading(1);
        // the empty block's newline must not keep the .paragraph it was
        // stamped with.
        let ns = NSMutableAttributedString(string: "Title\n\nbody")
        ns.addAttribute(
            SemanticNSBridge.blockStyleKey,
            value: BlockStyle.heading(1),
            range: NSRange(location: 0, length: 6)
        ) // "Title\n"
        ns.addAttribute(
            SemanticNSBridge.blockStyleKey,
            value: BlockStyle.paragraph,
            range: NSRange(location: 6, length: 5)
        ) // "\nbody"

        let decoded = SemanticNSBridge.attributedString(from: ns)
        let canonical = Sem.doc(Sem.block("Title", .heading(1)), Sem.block(""), Sem.block("body"))
        #expect(decoded == canonical)
        #expect(RichTextHTML.decode(RichTextHTML.encode(decoded)) == decoded)
    }

    @Test func documentStartingWithAnEmptyBlockLeavesItsNewlineBare() {
        let ns = NSMutableAttributedString(string: "\nabc")
        ns.addAttribute(
            SemanticNSBridge.blockStyleKey,
            value: BlockStyle.paragraph,
            range: NSRange(location: 0, length: ns.length)
        )

        let decoded = SemanticNSBridge.attributedString(from: ns)
        let canonical = Sem.doc(Sem.block(""), Sem.block("abc"))
        #expect(decoded == canonical)
        #expect(RichTextHTML.decode(RichTextHTML.encode(decoded)) == decoded)
    }

    @Test func documentEndingWithAnEmptyBlockLeavesItsNewlineBare() {
        // "abc\n\n": the first newline terminates the non-empty "abc" block
        // and legitimately keeps .paragraph; the second is the trailing,
        // empty final block's own newline and must come back bare.
        let ns = NSMutableAttributedString(string: "abc\n\n")
        ns.addAttribute(
            SemanticNSBridge.blockStyleKey,
            value: BlockStyle.paragraph,
            range: NSRange(location: 0, length: ns.length)
        )

        let decoded = SemanticNSBridge.attributedString(from: ns)
        let canonical = Sem.doc(Sem.block("abc"), Sem.block(""), Sem.block(""))
        #expect(decoded == canonical)
        #expect(RichTextHTML.decode(RichTextHTML.encode(decoded)) == decoded)
    }

    @Test func threeConsecutiveNewlinesLeaveTheMiddleOnesBare() {
        // "abc\n\n\ndef": two empty blocks in a row between "abc" and "def".
        let ns = NSMutableAttributedString(string: "abc\n\n\ndef")
        ns.addAttribute(
            SemanticNSBridge.blockStyleKey,
            value: BlockStyle.paragraph,
            range: NSRange(location: 0, length: ns.length)
        )

        let decoded = SemanticNSBridge.attributedString(from: ns)
        let canonical = Sem.doc(Sem.block("abc"), Sem.block(""), Sem.block(""), Sem.block("def"))
        #expect(decoded == canonical)
        #expect(RichTextHTML.decode(RichTextHTML.encode(decoded)) == decoded)
    }

    // MARK: - Tolerant decode

    @Test func unknownOrWrongTypedAttributesAreIgnoredWithoutCrashing() {
        let ns = NSMutableAttributedString(string: "abc")
        // Wrong-typed value under a known key.
        ns.addAttribute(
            SemanticNSBridge.blockStyleKey,
            value: "not a BlockStyle",
            range: NSRange(location: 0, length: 3)
        )
        // An unrelated custom key.
        ns.addAttribute(NSAttributedString.Key("com.example.bogus"), value: 42, range: NSRange(location: 0, length: 3))
        let result = SemanticNSBridge.attributedString(from: ns)
        #expect(String(result.characters) == "abc")
        #expect(result.runs.first?.blockStyle == nil)
    }

    // MARK: - semanticAttributes(block:typingAttributes:) (Fix 4)

    @Test func semanticAttributesForTypingOmitsBlockStyleWhenNil() {
        let attributes = SemanticNSBridge.semanticAttributes(block: nil, typingAttributes: TypingAttributes())
        #expect(attributes[SemanticNSBridge.blockStyleKey] == nil)
    }

    @Test func semanticAttributesForTypingIncludesBlockStyleWhenSet() {
        let attributes = SemanticNSBridge.semanticAttributes(block: .heading(2), typingAttributes: TypingAttributes())
        #expect(attributes[SemanticNSBridge.blockStyleKey] as? BlockStyle == .heading(2))
    }

    @Test func semanticAttributesForTypingIncludesOnlyTrueFlags() {
        var typing = TypingAttributes()
        typing.bold = true
        let attributes = SemanticNSBridge.semanticAttributes(block: nil, typingAttributes: typing)
        #expect(attributes[SemanticNSBridge.boldKey] as? Bool == true)
        #expect(attributes[SemanticNSBridge.italicKey] == nil)
        #expect(attributes[SemanticNSBridge.underlineKey] == nil)
        #expect(attributes[SemanticNSBridge.strikethroughKey] == nil)
    }

    @Test func semanticAttributesForTypingEachFlagIndependently() {
        for flag in InlineFlag.allCases {
            var typing = TypingAttributes()
            typing[flag] = true
            let attributes = SemanticNSBridge.semanticAttributes(block: nil, typingAttributes: typing)
            let key: NSAttributedString.Key = switch flag {
            case .bold: SemanticNSBridge.boldKey
            case .italic: SemanticNSBridge.italicKey
            case .underline: SemanticNSBridge.underlineKey
            case .strikethrough: SemanticNSBridge.strikethroughKey
            }
            #expect(attributes[key] as? Bool == true)
            #expect(attributes.count == 1)
        }
    }

    @Test func semanticAttributesForTypingIncludesColorWhenPresent() {
        var typing = TypingAttributes()
        typing.textColor = red
        let attributes = SemanticNSBridge.semanticAttributes(block: nil, typingAttributes: typing)
        #expect(attributes[SemanticNSBridge.textColorKey] as? RichTextColor == red)
    }

    @Test func semanticAttributesForTypingOmitsColorWhenAbsent() {
        let attributes = SemanticNSBridge.semanticAttributes(block: nil, typingAttributes: TypingAttributes())
        #expect(attributes[SemanticNSBridge.textColorKey] == nil)
    }

    // MARK: - typingAttributes(from:) (Fix 7)

    @Test func typingAttributesFromEmptyDictionaryIsAllDefaults() {
        let typing = SemanticNSBridge.typingAttributes(from: [:])
        #expect(typing == TypingAttributes())
    }

    @Test func typingAttributesFromEachFlagIndependently() {
        for flag in InlineFlag.allCases {
            let key: NSAttributedString.Key = switch flag {
            case .bold: SemanticNSBridge.boldKey
            case .italic: SemanticNSBridge.italicKey
            case .underline: SemanticNSBridge.underlineKey
            case .strikethrough: SemanticNSBridge.strikethroughKey
            }
            let typing = SemanticNSBridge.typingAttributes(from: [key: true])
            var expected = TypingAttributes()
            expected[flag] = true
            #expect(typing == expected)
        }
    }

    @Test func typingAttributesFromColorPresent() {
        let typing = SemanticNSBridge.typingAttributes(from: [SemanticNSBridge.textColorKey: red])
        #expect(typing.textColor == red)
    }

    @Test func typingAttributesFromColorAbsent() {
        let typing = SemanticNSBridge.typingAttributes(from: [:])
        #expect(typing.textColor == nil)
    }

    @Test func typingAttributesFromBlockStylePresent() {
        let typing = SemanticNSBridge.typingAttributes(from: [SemanticNSBridge.blockStyleKey: BlockStyle.heading(2)])
        #expect(typing.blockStyle == .heading(2))
    }

    @Test func typingAttributesFromBlockStyleAbsent() {
        let typing = SemanticNSBridge.typingAttributes(from: [:])
        #expect(typing.blockStyle == nil)
    }

    @Test func typingAttributesFromGarbageValuesAreIgnored() {
        let garbage: [NSAttributedString.Key: Any] = [
            SemanticNSBridge.blockStyleKey: "not a BlockStyle",
            SemanticNSBridge.boldKey: "not a Bool",
            SemanticNSBridge.italicKey: 42,
            SemanticNSBridge.underlineKey: NSObject(),
            SemanticNSBridge.strikethroughKey: [1, 2, 3],
            SemanticNSBridge.textColorKey: "not a RichTextColor",
            NSAttributedString.Key("com.example.bogus"): true,
        ]
        let typing = SemanticNSBridge.typingAttributes(from: garbage)
        #expect(typing == TypingAttributes())
    }

    @Test func typingAttributesFromIsTheInverseOfSemanticAttributesForTyping() {
        var original = TypingAttributes()
        original.bold = true
        original.strikethrough = true
        original.textColor = red
        original.blockStyle = .listItem(.ordered, depth: 1)
        let semantic = SemanticNSBridge.semanticAttributes(block: original.blockStyle, typingAttributes: original)
        let roundTripped = SemanticNSBridge.typingAttributes(from: semantic)
        #expect(roundTripped == original)
    }

    // MARK: - Agreement with the serializer

    @Test func roundTrippedDocumentEncodesToTheSameHTMLAsTheOriginal() {
        let doc = Sem.doc(
            Sem.with(Sem.block("Title", .heading(1)), bold: true),
            Sem.block("Body text")
        )
        let bridged = roundTrip(doc)
        #expect(bridged == doc)
        #expect(RichTextHTML.encode(bridged) == RichTextHTML.encode(doc))
    }
}
