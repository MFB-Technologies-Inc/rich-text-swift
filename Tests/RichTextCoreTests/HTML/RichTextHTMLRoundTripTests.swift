// RichTextHTMLRoundTripTests.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
@testable import RichTextCore
import Testing

struct RichTextHTMLRoundTripTests {
    private func modelCases() -> [AttributedString] {
        var boldRed = Sem.block("hi"); boldRed.bold = true
        boldRed.textColor = RichTextColor(red: 255, green: 0, blue: 0)
        return [
            Sem.block("Hello"),
            Sem.block("Title", .heading(1)),
            Sem.block("a & b < c"),
            Sem.block("a\u{2028}b"),
            boldRed,
            Sem.doc(Sem.block("H", .heading(2)), Sem.block("body")),
            Sem.doc(
                Sem.block("one", .listItem(.ordered, depth: 0)),
                Sem.block("two", .listItem(.ordered, depth: 0))
            ),
            Sem.doc(
                Sem.block("a", .listItem(.unordered, depth: 0)),
                Sem.block("b", .listItem(.unordered, depth: 1)),
                Sem.block("c", .listItem(.unordered, depth: 0))
            ),
            // F5: blockquote is a real role now, not a degraded paragraph.
            Sem.block("quoted", .blockquote),
            Sem.doc(
                Sem.block("Title", .heading(1)),
                Sem.block("quoted", .blockquote),
                Sem.block("a", .listItem(.unordered, depth: 0)),
                Sem.block("body")
            ),
        ]
    }

    @Test func modelRoundTripsThroughHTML() {
        for model in modelCases() {
            #expect(RichTextHTML.decode(RichTextHTML.encode(model)) == model)
        }
    }

    @Test func canonicalHTMLIsIdempotent() {
        // F6: the nested-list entry here used to be
        // `<ul><li>a</li><ul><li>b</li></ul><li>c</li></ul>`, an invalid
        // shape (a `<ul>` as a direct child of `<ul>`, rather than nested
        // inside the preceding `<li>`) — updated to the valid form the
        // encoder now emits.
        let canonical = [
            "<p>Hello</p>",
            "<h1>Title</h1>",
            "<p><span style=\"color:#ff0000\"><b>hi</b></span></p>",
            "<ul><li>a<ul><li>b</li></ul></li><li>c</li></ul>",
            "<p>a<br>b</p>",
            "<blockquote>quoted</blockquote>",
            "<blockquote><b>quoted</b></blockquote>",
            "<ul><li>a</li></ul>\n<blockquote>q</blockquote>\n<p>after</p>",
        ]
        for html in canonical {
            #expect(RichTextHTML.encode(RichTextHTML.decode(html)) == html)
        }
    }

    @Test func tolerantVariantsNormalizeToCanonical() {
        #expect(RichTextHTML.encode(RichTextHTML.decode("<p><strong>x</strong></p>")) == "<p><b>x</b></p>")
        #expect(RichTextHTML.encode(RichTextHTML.decode("<p><em>x</em></p>")) == "<p><i>x</i></p>")
        #expect(RichTextHTML.encode(RichTextHTML.decode("<p><del>x</del></p>")) == "<p><s>x</s></p>")
        #expect(RichTextHTML.encode(RichTextHTML.decode("<p><span style=\"color:red\">x</span></p>"))
            == "<p><span style=\"color:#ff0000\">x</span></p>")
    }

    /// The legacy-editor (ZSS/WebKit) and pasted-content color shapes, pinned
    /// end to end: each must normalize to canonical `color:#rrggbb` (or no
    /// color). Mirrors the text-color findings' probe corpus.
    @Test(arguments: [
        (
            "<div><span style=\"color: rgb(255, 59, 48);\">z</span></div>",
            "<p><span style=\"color:#ff3b30\">z</span></p>"
        ),
        ("<div>\n  <span style=\"color: rgb(0, 0, 0);\">z</span>\n</div>", "<p>z</p>"),
        ("<p><font color=\"#ff0000\">z</font></p>", "<p><span style=\"color:#ff0000\">z</span></p>"),
        ("<p><font color=\"red\">z</font></p>", "<p><span style=\"color:#ff0000\">z</span></p>"),
        ("<p><span style=\"color: rgba(255, 0, 0, 1)\">z</span></p>", "<p><span style=\"color:#ff0000\">z</span></p>"),
        (
            "<p><span style=\"color: rgba(255, 0, 0, 0.5)\">z</span></p>",
            "<p><span style=\"color:#ff0000\">z</span></p>"
        ),
        ("<p><span style=\"color: rgba(255, 0, 0, 0.2)\">z</span></p>", "<p>z</p>"),
        ("<p><span style=\"color: rgb(100%, 0%, 0%)\">z</span></p>", "<p><span style=\"color:#ff0000\">z</span></p>"),
        ("<p><span style=\"color: rgb(255 0 0)\">z</span></p>", "<p><span style=\"color:#ff0000\">z</span></p>"),
        ("<p><span style=\"color: hsl(0, 100%, 50%)\">z</span></p>", "<p><span style=\"color:#ff0000\">z</span></p>"),
        ("<p><span style=\"color: #FF0000 !important\">z</span></p>", "<p><span style=\"color:#ff0000\">z</span></p>"),
        (
            "<p><span style=\"color:#1F497D;mso-themecolor:text2\">z</span></p>",
            "<p><span style=\"color:#1f497d\">z</span></p>"
        ),
        ("<p><span style=\"color:windowtext\">z</span></p>", "<p>z</p>"),
        ("<p><span style=\"color: darkred\">z</span></p>", "<p><span style=\"color:#8b0000\">z</span></p>"),
        ("<p><span style=\"color:red;color:blue\">z</span></p>", "<p><span style=\"color:#0000ff\">z</span></p>"),
        (
            "<p><span style=\"color:#ff0000\">a<span style=\"color:#000000\">b</span>c</span></p>",
            "<p><span style=\"color:#ff0000\">a</span>b<span style=\"color:#ff0000\">c</span></p>"
        ),
    ])
    func legacyColorShapesNormalizeToCanonical(_ input: String, _ canonical: String) {
        #expect(RichTextHTML.encode(RichTextHTML.decode(input)) == canonical)
    }

    @Test func decodeNeverCrashesOnAdversarialInput() {
        let fragments = [
            "<",
            ">",
            "<p>",
            "</p>",
            "<b>",
            "</i>",
            "<ul>",
            "<li>",
            "&amp;",
            "<span style=\"color:\">",
            "text",
            "<br>",
            "<<>>",
            "&#;",
            "<h9>",
        ]
        // Deterministic permutations (indices, not RNG).
        for a in 0 ..< fragments.count {
            for b in 0 ..< fragments.count {
                for c in 0 ..< fragments.count {
                    let html = fragments[a] + fragments[b] + fragments[c]
                    let model = RichTextHTML.decode(html) // must not crash
                    let once = RichTextHTML.encode(model)
                    let twice = RichTextHTML.encode(RichTextHTML.decode(once))
                    #expect(once == twice) // re-encode is stable
                }
            }
        }
    }

    /// Deterministic random truncations of otherwise-valid HTML: chop a
    /// canonical string at every possible prefix length and assert decode
    /// never crashes and the resulting re-encode is stable.
    // MARK: - Black is the absence of a color (Important 1)

    //
    // Neither the round-trip suite above nor the fuzzers below could
    // previously produce black: `modelCases()` uses red only, and
    // `modelFuzzRoundTrips`'s color pool used two non-black colors. These pin
    // the *documented* behavior at both ends: a canonical (non-black)
    // document round-trips exactly, while a document carrying explicit black
    // is not canonical (see `RichTextHTML.encode`'s doc comment) and does not
    // survive the round trip unchanged — it loses the color instead.

    @Test func aCanonicalDocumentWithANonBlackColorRoundTrips() {
        var doc = Sem.block("hi")
        doc.textColor = RichTextColor(red: 0, green: 128, blue: 255)
        #expect(RichTextHTML.decode(RichTextHTML.encode(doc)) == doc)
    }

    @Test func aDocumentCarryingExplicitBlackIsNotCanonicalAndLosesTheColorAcrossTheRoundTrip() {
        var doc = Sem.block("hi")
        doc.textColor = RichTextColor(red: 0, green: 0, blue: 0)

        let html = RichTextHTML.encode(doc)
        #expect(html == "<p>hi</p>") // no <span style="color:...">

        var expected = doc
        expected.textColor = nil
        let decoded = RichTextHTML.decode(html)
        #expect(decoded == expected)
        #expect(decoded != doc) // NOT a round trip: black does not survive
    }

    @Test func decodeNeverCrashesOnTruncatedInput() {
        // F6: the nested-list source is the valid form (a nested list inside
        // its parent <li>) — the encoder no longer emits the invalid sibling
        // form this previously used.
        let sources = [
            "<p><span style=\"color:#ff0000\"><b>hi</b></span></p>",
            "<ul><li>a<ul><li>b</li></ul></li><li>c</li></ul>",
            "<p>a<br>b</p>",
            "<h2><i>Title</i></h2>",
            "<blockquote>quoted</blockquote>",
        ]
        for source in sources {
            let chars = Array(source)
            for cut in 0 ... chars.count {
                let prefix = String(chars[0 ..< cut])
                let model = RichTextHTML.decode(prefix) // must not crash
                let once = RichTextHTML.encode(model)
                let twice = RichTextHTML.encode(RichTextHTML.decode(once))
                #expect(once == twice) // re-encode is stable
            }
        }
    }

    /// The canonical form of a fuzzed document, for comparison purposes only:
    /// every explicit black `textColor` (the fuzz pool below includes one)
    /// stripped to `nil`, matching what `RichTextHTML.encode` actually does.
    /// A document with no black run is unaffected, so this is a safe
    /// expectation for every case the fuzz loop generates, not just the
    /// black one.
    private func canonicalized(_ text: AttributedString) -> AttributedString {
        var result = text
        for run in text.runs where run.textColor == RichTextColor(red: 0, green: 0, blue: 0) {
            result[run.range].textColor = nil
        }
        return result
    }

    /// Deterministic model fuzz: build semantic docs from a fixed component
    /// list using index-based combinations (no RNG), and assert the model
    /// round-trips through HTML into its canonical form — identity for every
    /// case except the explicit-black one, which the pool includes so the
    /// black-is-absent-color normalization is exercised by the fuzzer itself,
    /// not only by the hand-written cases above.
    @Test func modelFuzzRoundTrips() {
        let texts = ["a", "bc", "x y", "a & b"]
        let styles: [BlockStyle] = [
            .paragraph, .heading(1), .heading(2),
            .listItem(.unordered, depth: 0), .listItem(.ordered, depth: 0),
            .blockquote,
        ]
        let attributeSetters: [(inout AttributedString) -> Void] = [
            { _ in },
            { $0.bold = true },
            { $0.italic = true },
            { $0.underline = true },
            { $0.strikethrough = true },
            { $0.bold = true; $0.italic = true },
            { $0.textColor = RichTextColor(red: 0, green: 128, blue: 255) },
            { $0.bold = true; $0.textColor = RichTextColor(red: 10, green: 20, blue: 30) },
            { $0.textColor = RichTextColor(red: 0, green: 0, blue: 0) },
        ]

        for t in 0 ..< texts.count {
            for s in 0 ..< styles.count {
                for a in 0 ..< attributeSetters.count {
                    var block = Sem.block(texts[t], styles[s])
                    attributeSetters[a](&block)
                    #expect(RichTextHTML.decode(RichTextHTML.encode(block)) == canonicalized(block))
                }
            }
        }

        // Multi-block combinations (index-based pairing, not exhaustive product,
        // to keep the suite fast while still deterministic).
        for i in 0 ..< texts.count {
            let j = (i + 1) % texts.count
            var first = Sem.block(texts[i], styles[i % styles.count])
            attributeSetters[i % attributeSetters.count](&first)
            var second = Sem.block(texts[j], styles[j % styles.count])
            attributeSetters[j % attributeSetters.count](&second)
            let doc = Sem.doc(first, second)
            #expect(RichTextHTML.decode(RichTextHTML.encode(doc)) == canonicalized(doc))
        }
    }
}
