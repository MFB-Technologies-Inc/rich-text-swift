// HTMLParsing-benchmarks.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Benchmark
import RichTextCore

private let inputThroughput = BenchmarkMetric.custom(
    "Input throughput (MB/s)",
    polarity: .prefersLarger,
    useScalingFactor: false
)

private enum Fixtures {
    /// The two hex arrays are deliberately the same length. Each benchmark
    /// iteration parses the whole array, so the reported time is per-array, not
    /// per-parse.
    static let validHexColors = [
        "#f00", "0af", "#FF0000", "0080ff", "  #663399  ", "#ABCdef",
    ]

    static let invalidHexColors = [
        "", "#12", "#1234", "#gg0000", "transparent", "not-a-color",
    ]

    static let entitiesAndWhitespace = """
    <p>  Fish &amp; chips &mdash; &#169; &#x1F600;  </p>\r
    <p>Tabs\tand       spaces &lt;stay&gt; safe&nbsp;here.</p>
    """

    static let inlineFormatting = """
    <p><strong>bold <em>italic <u>underlined <del>struck</del></u></em></strong>
    plain <b><i><ins><strike>aliases</strike></ins></i></b><br>next line</p>
    """

    static let cssColors = """
    <p>
      <span style="color:#f00">hex</span>
      <span style="color:rgb(0, 128, 255)">rgb</span>
      <span style="color:rgb(100% 0% 50% / 80%)">modern rgb</span>
      <span style="color:hsl(120, 100%, 25%)">hsl</span>
      <span style="color:hsl(0.5turn 100% 50%)">modern hsl</span>
      <span style="color:rebeccapurple">named</span>
      <span style="color:red !important; color:blue">cascade</span>
      <font color="cornflowerblue">legacy</font>
      <span style="color:rgba(255, 0, 0, 0.1)">transparent</span>
    </p>
    """

    static let blockStructure = """
    <h1>Document title</h1>
    <p>Opening paragraph.</p>
    <blockquote><p>Quoted paragraph.</p><blockquote>Nested quote.</blockquote></blockquote>
    <ol><li>First<ul><li>Nested A</li><li>Nested B</li></ul></li><li>Second</li></ol>
    <h2>Section</h2><div>First line</div><div>Second line</div><hr>
    """

    static let tolerantHTML = """
    <!doctype html><!-- ignored --><style>p{color:red}</style><script>alert(1)</script>
    <p class=test disabled data-value='a&amp;b'>before<img src="x"><unknown>kept</unknown>
    <b>mismatched</u></b><o:p></o:p><w:t>word text</w:t><br/>after</p>
    <meta charset="utf-8"><link rel=stylesheet><p>unterminated <span title="value">content</p>
    """

    /// An unterminated `<!--`, the worst case for the tokenizer's comment scan.
    ///
    /// `HTMLTokenizer.skipUntil` walks to EOF looking for `-->` and asks
    /// `hasPrefix` at every single character, and `hasPrefix` builds a fresh
    /// `Array("-->")` on each of those calls.
    static let unterminatedComment =
        "<p>before the comment</p><!-- " + String(repeating: "comment body text ", count: 1000)

    /// A ~100-section document, the headline "large input" case.
    static let realisticDocument = document(sections: 100)

    /// Builds a document of `sections` sections, each one different from the
    /// others: its own heading level, prose length, inline tags, CSS color
    /// notation, list kind, and list length.
    ///
    /// The generator is a fixed-seed LCG rather than `Int.random(in:)` because
    /// the fixture has to be byte-identical on every run: two runs whose input
    /// differs produce numbers that cannot be compared.
    static func document(sections: Int) -> String {
        var seed: UInt64 = 0x2545_F491_4F6C_DD1D
        func random(_ bound: Int) -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((seed >> 33) % UInt64(bound))
        }

        let vocabulary = """
        rendering pipeline attachment selection paragraph marker caret toolbar \
        heading quotation emphasis fragment document boundary whitespace entity \
        attribute traversal coalescing normalization cursor glyph baseline offset
        """
        .split(whereSeparator: \.isWhitespace)
        .map(String.init)

        let inlineTags = ["strong", "em", "u", "b", "i", "del", "ins"]
        let colorNotations = [
            "#336699", "rgb(0, 128, 255)", "hsl(210 75% 45%)", "cornflowerblue",
            "rgba(12, 34, 56, 0.8)", "hsl(0.25turn 60% 40%)", "#c9f",
        ]

        func words(_ count: Int) -> String {
            (0 ..< count).map { _ in vocabulary[random(vocabulary.count)] }.joined(separator: " ")
        }

        var html = "<h1>\(words(4))</h1>"
        for index in 0 ..< sections {
            let level = 2 + index % 4
            let emphasis = inlineTags[random(inlineTags.count)]
            let listEmphasis = inlineTags[random(inlineTags.count)]
            let color = colorNotations[random(colorNotations.count)]

            html += "<h\(level)>\(words(2 + random(4)))</h\(level)>"
            html += "<p>\(words(6 + random(20))) <\(emphasis)>\(words(1 + random(3)))</\(emphasis)>"
            html += " \(words(3 + random(8))) &amp; "
            html += "<span style=\"color:\(color)\">\(words(1 + random(4)))</span>.</p>"

            if random(3) != 0 {
                html += "<blockquote><p>\(words(5 + random(12)))<br>\(words(3 + random(6)))</p></blockquote>"
            }

            let listTag = random(2) == 0 ? "ul" : "ol"
            html += "<\(listTag)>"
            for _ in 0 ..< (2 + random(4)) {
                html += "<li>\(words(2 + random(6))) <\(listEmphasis)>\(words(1 + random(2)))</\(listEmphasis)></li>"
            }
            html += "</\(listTag)>"
        }
        return html
    }
}

private func registerHexBenchmark(_ name: String, values: [String]) {
    Benchmark(name) { benchmark in
        for _ in benchmark.scaledIterations {
            for value in values {
                blackHole(RichTextColor(hex: value))
            }
        }
    }
}

private func registerDecodeBenchmark(_ name: String, html: String) {
    Benchmark(name) { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(RichTextHTML.decode(html))
        }
    }
}

/// Reports decimal megabytes of UTF-8 HTML parsed per second in addition to
/// the library's normal latency and operations-per-second metrics.
private func registerThroughputDecodeBenchmark(_ name: String, html: String) {
    let inputBytes = html.utf8.count
    Benchmark(
        name,
        configuration: .init(metrics: [.wallClock, .throughput, inputThroughput])
    ) { benchmark in
        let clock = ContinuousClock()
        benchmark.startMeasurement()
        let elapsed = clock.measure {
            for _ in benchmark.scaledIterations {
                blackHole(RichTextHTML.decode(html))
            }
        }
        benchmark.stopMeasurement()

        let components = elapsed.components
        let seconds = Double(components.seconds)
            + Double(components.attoseconds) / 1_000_000_000_000_000_000
        let processedBytes = inputBytes * benchmark.scaledIterations.count
        let megabytesPerSecond = Double(processedBytes) / 1_000_000 / seconds
        benchmark.measurement(inputThroughput, Int(megabytesPerSecond.rounded()))
    }
}

/// The decode happens here, at registration time, so only the encode lands
/// inside the measured closure.
private func registerEncodeBenchmark(_ name: String, html: String) {
    let document = RichTextHTML.decode(html)
    Benchmark(name) { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(RichTextHTML.encode(document))
        }
    }
}

/// `decode(encode(x))` on a semantic model: the loop the editor runs every time
/// a document is saved and reopened.
private func registerRoundTripBenchmark(_ name: String, html: String) {
    let document = RichTextHTML.decode(html)
    Benchmark(name) { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(RichTextHTML.decode(RichTextHTML.encode(document)))
        }
    }
}

let benchmarks: @Sendable () -> Void = {
    registerHexBenchmark("Parse color/valid hex batch", values: Fixtures.validHexColors)
    registerHexBenchmark("Parse color/invalid hex batch", values: Fixtures.invalidHexColors)

    registerDecodeBenchmark("Parse HTML/entities and whitespace", html: Fixtures.entitiesAndWhitespace)
    registerDecodeBenchmark("Parse HTML/inline formatting", html: Fixtures.inlineFormatting)
    registerDecodeBenchmark("Parse HTML/CSS colors", html: Fixtures.cssColors)
    registerDecodeBenchmark("Parse HTML/block structure", html: Fixtures.blockStructure)
    registerDecodeBenchmark("Parse HTML/tolerant input", html: Fixtures.tolerantHTML)
    registerDecodeBenchmark("Parse HTML/unterminated comment", html: Fixtures.unterminatedComment)

    registerThroughputDecodeBenchmark(
        "Parse HTML/large realistic document",
        html: Fixtures.realisticDocument
    )
    registerEncodeBenchmark("Encode HTML/large realistic document", html: Fixtures.realisticDocument)
    registerRoundTripBenchmark("Round trip HTML/large realistic document", html: Fixtures.realisticDocument)

    // A size series on one fixture, four times larger at each step.
    //
    // `HTMLDecoder.finish()` concatenates the finished blocks with
    // `result += AttributedString(…)` once per block, and `HTMLEncoder` builds
    // its output by appending to a `String`. Either could turn quadratic in
    // block count under a refactor.
    //
    // Sizes are zero-padded so the three rows sort in order in the report.
    for sections in [10, 40, 160] {
        let label = String(format: "%03d", sections)
        let html = Fixtures.document(sections: sections)
        registerDecodeBenchmark("Parse HTML/scaling/\(label) sections", html: html)
        registerEncodeBenchmark("Encode HTML/scaling/\(label) sections", html: html)
    }
}
