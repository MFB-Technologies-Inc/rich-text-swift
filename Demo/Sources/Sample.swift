// Sample.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

/// Documents that each exercise one area of the package.
struct Sample: Identifiable {
    let name: String
    let summary: String
    let html: String

    var id: String {
        name
    }

    static let all: [Sample] = [
        Sample(
            name: "Everything",
            summary: "Every v1 feature in one document",
            html: """
            <h1>SwiftRichText</h1>\
            <p>Body text with <b>bold</b>, <i>italic</i>, <u>underline</u>, <s>strikethrough</s>, \
            and <span style="color:#ff3b30">color</span>.</p>\
            <h2>Lists</h2>\
            <ul><li>first</li><li><b>second</b></li></ul>\
            <ol><li>one</li><li>two</li><li>three</li></ol>\
            <h3>Small heading</h3>\
            <p>The end.</p>
            """
        ),
        Sample(
            name: "Empty",
            summary: "No characters, so the placeholder shows",
            html: ""
        ),
        Sample(
            name: "Inline formatting",
            summary: "Overlapping and nested inline styles",
            html: """
            <p><b>bold <i>bold italic <u>bold italic underline</u></i></b></p>\
            <p><s>struck <span style="color:#007aff">struck blue</span></s> plain</p>\
            <p><span style="color:#34c759">green</span> <span style="color:#ff9500">orange</span> \
            <span style="color:#af52de">purple</span></p>
            """
        ),
        Sample(
            name: "Nested lists",
            summary: "Unordered and ordered lists, nested and mixed",
            html: """
            <ul><li>top level<ul><li>nested bullet<ul><li>third level</li></ul></li></ul></li>\
            <li>back to top</li></ul>\
            <ol><li>step one<ol><li>sub-step a</li><li>sub-step b</li></ol></li><li>step two</li></ol>\
            <ul><li>bullet<ol><li>numbered inside a bullet</li></ol></li></ul>
            """
        ),
        Sample(
            name: "Headings",
            summary: "H1 to H3 with inline formatting inside",
            html: """
            <h1>Heading 1</h1><p>paragraph</p>\
            <h2>Heading <i>2</i></h2><p>paragraph</p>\
            <h3><span style="color:#ff3b30">Heading 3</span></h3><p>paragraph</p>
            """
        ),
        Sample(
            name: "Messy import",
            summary: "Non-canonical tags, CSS colors, entities, unknown tags",
            html: """
            <div><strong>strong</strong> <em>em</em> <strike>strike</strike> \
            <font color="red">font red</font></div>\
            <p><span style="color: rgb(0, 122, 255)">rgb()</span> \
            <span style="color: hsl(120, 100%, 25%)">hsl()</span> \
            <span style="color: rebeccapurple">named</span></p>\
            <p>&lt;tag&gt; &amp; &quot;quotes&quot; &copy; &#x1F600;</p>\
            <p><a href="https://example.com">link text survives</a>, \
            <img alt="alt text survives"> and <img src="x.png"> vanishes</p>\
            <table><tr><td>table cell</td></tr></table>
            """
        ),
        Sample(
            name: "Long document",
            summary: "200 paragraphs, for scrolling and typing lag",
            html: (1 ... 200).map { index in
                index.isMultiple(of: 10)
                    ? "<h2>Section \(index / 10)</h2>"
                    : "<p>Paragraph \(index) with <b>some</b> <i>inline</i> formatting.</p>"
            }.joined()
        ),
    ]
}
