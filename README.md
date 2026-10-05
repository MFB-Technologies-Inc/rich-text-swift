# SwiftRichText

[![CI](https://github.com/MFB-Technologies-Inc/rich-text-swift/actions/workflows/ci.yml/badge.svg)](https://github.com/MFB-Technologies-Inc/rich-text-swift/actions/workflows/ci.yml)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FMFB-Technologies-Inc%2Frich-text-swift%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/MFB-Technologies-Inc/rich-text-swift)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FMFB-Technologies-Inc%2Frich-text-swift%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/MFB-Technologies-Inc/rich-text-swift)

A native SwiftUI rich text editor for iOS, backed by `AttributedString`, that round-trips to clean,
minimal HTML.

```swift
import SwiftRichText

struct NoteEditor: View {
    @State private var document = RichTextHTML.decode("<p>Hello</p>")

    var body: some View {
        RichTextEditor(text: $document)
            .richTextToolbar(.html)
    }
}
```

## Why

Most rich text on iOS is either a `WKWebView` pretending to be an editor, or `NSAttributedString`'s
built-in HTML conversion — which emits hundreds of bytes of inline CSS for a bold word. SwiftRichText
is real TextKit 2, and its documents serialize to HTML a human would write:

```html
<h1>Title</h1>
<ul><li>first</li><li><b>second</b></li></ul>
<p>Body text with <span style="color:#ff3b30">color</span>.</p>
```

## Requirements

iOS 17+. Swift 6, strict concurrency. No third-party dependencies.

## Installation

```swift
.package(url: "https://github.com/MFB-Technologies-Inc/rich-text-swift.git", from: "1.0.0")
```

## Usage

### The editor

`RichTextEditor` binds an `AttributedString` — that is the document currency, not HTML:

```swift
RichTextEditor(
    text: $document,
    isEditable: permission == .write,   // read-only disables typing and the toolbar
    placeholder: "Enter text here",     // shown while the document is empty
    pasteAsPlainText: true              // strip formatting from pasted content
)
```

Documents assigned through this binding convert CRLF, lone CR, U+2029 and U+0085 line endings to
LF block separators while preserving the document's formatting. When that changes the document, the editor
writes the converted document back to the binding on the next run loop turn, so opening a CRLF
document marks it as changed. Nothing else is written back on open.

`pasteAsPlainText` is off by default, which keeps `UITextView`'s own rich paste. Turn it on when
your documents arrive from Word or Outlook: a rich paste keeps the pasteboard's fonts and colors on
screen while the saved document drops them, so what the user sees is not what gets saved. With the
option on, pasted text adopts the caret's own block role and inline formatting, Windows line endings
become block separators, and a pasteboard holding no text at all — an image, say — inserts nothing
rather than falling back to a rich paste.

### The toolbar

`.richTextToolbar(_:placement:)` renders the built-in controls. Two presets ship, or pass your own
list in the order you want them:

```swift
.richTextToolbar()                                   // .default — inline formatting plus lists
.richTextToolbar(.html)                              // .default plus H1–H3
.richTextToolbar([.bold, .italic, .heading(.h1)])    // exactly these, in this order
.richTextToolbar(.html, placement: .top)             // above the editor; .bottom is the default
```

A bottom-placed bar rides above the keyboard, since SwiftUI's keyboard safe area insets it.

### Persistence

Two options, depending on whether you need portability or exactness.

**HTML** — the canonical format, and what you want if anything else will ever read the document:

```swift
let html = RichTextHTML.encode(document)      // save
let document = RichTextHTML.decode(html)      // load
```

HTML is deliberately *not* on the keystroke path: convert at your save and load boundaries only.

The dialect is small and closed: `<p>`, `<h1>`–`<h3>`, `<ul>`/`<ol>`/`<li>` (nested), `<b>`, `<i>`,
`<u>`, `<s>`, and `<span style="color:#rrggbb">`. Import is tolerant — `<strong>`, `<em>`,
`<strike>`, `<font color>`, CSS colors (hex, all named colors, `rgb()`/`rgba()`/`hsl()`), and
entities are all normalized, and unknown tags are unwrapped so their text survives. Canonical documents satisfy `decode(encode(x)) == x`.
A list item more than one level deeper than the item before it gets one `<li style="display:block">`
per skipped level to hold the nested list, so the HTML stays valid and a browser draws no marker
for the skipped level.

Tags outside the dialect are text-preserving but attribute-dropping: a `<a href="...">link</a>`
imports as the word *link* with no href, and an `<img alt="chart">` imports as the word *chart* (an
`<img>` with no `alt` leaves nothing behind). Nothing silently disappears, but nothing outside the
dialect survives a round trip either — links and images are post-v1 work.

**Codable** — lossless, for when you own both ends (drafts, autosave, undo snapshots):

```swift
struct Note: Codable {
    @CodableConfiguration(from: \.richText) var body = AttributedString()
}
```

This keeps everything HTML normalizes away, at the cost of a Foundation-shaped blob no other client
can read.

The format is stable: block roles encode as `{"type":"heading","level":1}`-style objects and colors
as `"#rrggbb"`, both hand-written rather than synthesized, so documents saved with one version of
SwiftRichText decode with the next. A change to it is a breaking change and will be called out in
the release notes.

## What v1 supports

Bold, italic, underline, strikethrough, text color, bulleted and numbered lists, and H1–H3.

Deliberately not in v1, all additive later: links, highlight, blockquote, more heading levels, font
size and family, soft breaks, Markdown, list indent/outdent authoring, and a macOS port. Known
deferrals and defects are tracked in [GitHub Issues](https://github.com/MFB-Technologies-Inc/rich-text-swift/issues).

## Design

Three layers, so a macOS port is additive rather than a rewrite:

| Layer | Module | Depends on |
|---|---|---|
| Model + serialization | `RichTextCore` | Foundation only |
| Editing engine | `RichTextEngine` | Foundation, with UIKit confined to one subfolder |
| SwiftUI wrapper | `RichTextEditorUI` | SwiftUI + UIKit |

A block's role — paragraph, heading, list item — lives in an invisible `AttributedString` attribute
that is the single source of truth for serialization. It is never inferred from visual attributes
like font size, and presentation is never stored in the document: list bullets and numbers are drawn
at layout time, not inserted as text. CI enforces the layer boundaries mechanically.

## Documentation

Every public symbol carries doc comments, so Xcode's Quick Help works with no extra setup.

To build the browsable DocC archive, opt in with `SWIFTRICHTEXT_DOCS=1` — this is the one and only
dependency, it is build-time only, and it stays out of your dependency graph unless you ask for it:

```bash
SWIFTRICHTEXT_DOCS=1 swift package generate-documentation --target RichTextCore
```

`RichTextEditor` and `.richTextToolbar` are `#if os(iOS)`, so a host-platform docs build omits them.
Build for an iOS destination to document the UI layer:

```bash
SWIFTRICHTEXT_DOCS=1 xcodebuild docbuild -scheme rich-text-swift-Package \
  -destination 'generic/platform=iOS'
```

## Benchmarks

To run the benchmark suite, opt in with `SWIFTRICHTEXT_BENCHMARK=1`.

```bash
# Run all benchmarks with standard formatting
SWIFTRICHTEXT_BENCHMARK=1 swift package benchmark

# Run all benchmarks with markdown formatting
SWIFTRICHTEXT_BENCHMARK=1 swift package benchmark --format markdown

# Run only the 'realist document' benchmark which includes throughput
SWIFTRICHTEXT_BENCHMARK=1 swift package benchmark run --filter '^Parse HTML/large realistic document$'
```

The benchmark suite is not intended for running in CI. The hosted workflow runners are not consistent enough for reliable benchmarking. They should instead be used locally before and after changes. It is recommended that all applications be closed during a benchmark run.

### Comparing results

`Scripts/benchmark` wraps the plugin's baseline commands so you can see what a change did. The
common case is measuring your working tree against the branch it came from:

```bash
# Benchmark main, then the working tree, and print the difference
Scripts/benchmark diff main

# Same, limited to one benchmark
Scripts/benchmark diff main --filter '^Parse HTML/large realistic document$'

# Two commits against each other
Scripts/benchmark diff main parse-performance
```

`--filter` has to match the whole benchmark name, so use `'Parse HTML/.*'` rather than
`'^Parse HTML/'`. A filter that matches nothing makes the script fail rather than save an empty
result.

A ref is benchmarked from its committed code in a scratch worktree at `.build/benchmark-worktree`,
so uncommitted edits never leak into it. The worktree is reused between runs to keep rebuilds
incremental. The first run builds the benchmark dependencies from scratch, and later ones take
about a minute for a single filtered benchmark. `Scripts/benchmark clean` removes it.

You can also store and compare baselines by hand with `save <name>`, `save-ref <ref> [<name>]`,
`compare <name> [<other>]`, `list`, and `delete <name>`. Pass `--markdown` to get tables you can
paste into a PR. Baselines live in `.benchmarkBaselines/`, which is gitignored because the numbers
only mean something on the machine that produced them. `diff` saves its refs as `diff-<ref>`, so
it never overwrites a baseline you saved by hand.

> Note: the fixtures are part of the benchmarked code. If a ref changes
> `Benchmarks/RichTextCore-benchmarks/HTMLParsing-benchmarks.swift`, the two sides measured
> different inputs and the comparison doesn't hold.

## Demo app

`Demo/` holds an iOS app for trying the editor by hand. It has three tabs: the editor itself, with
every `RichTextEditor` and `.richTextToolbar` option switchable from an Options sheet; the live
`RichTextHTML.encode` output with two round-trip checks; and a Load tab with sample documents and a
field for pasting your own HTML. The project is generated with [Tuist](https://tuist.dev), pinned
in `mise.toml`:

```bash
cd Demo
mise install
tuist install 
tuist generate
```

The app depends on the package by path, so edits under `Sources/` show up on the next build without
regenerating. The generated `.xcodeproj` and `.xcworkspace` are gitignored. Regenerate after
adding or removing a file in `Demo/Sources`.

[`Demo/ManualTesting.md`](Demo/ManualTesting.md) is the script for what the
tests can't reach: pasting real clipboard content and undo with the real keyboard.

## Contributing

Contributions are welcome: bug reports, fixes, tests, and docs.

### Reporting a bug

Open a [GitHub issue](https://github.com/MFB-Technologies-Inc/rich-text-swift/issues) with:

- The steps to reproduce it, ideally starting from HTML you can paste into the Demo app's Load tab.
- What you expected and what happened.
- The iOS version and the device or simulator.

For an HTML round-trip problem, include the input HTML and what `RichTextHTML.encode` produced.

### Proposing a change

For anything beyond a small fix, open an issue first so we can agree on the approach before you
write the code. Two kinds of change in particular need agreement first:

- A new feature: [What v1 supports](#what-v1-supports) lists what's deliberately out of scope.
- A change to the HTML the encoder writes, which every app that stores it depends on.

### Development setup

You'll need Xcode with an iOS simulator and [mise](https://mise.jdx.dev), which installs the pinned
SwiftFormat and SwiftLint:

```bash
mise install
```

Open `Package.swift` in Xcode to work on the package, or use the [Demo app](#demo-app) to try your
change by hand.

### Before you open a pull request

Run both test suites. `swift test` covers the model, the HTML and the editing engine on macOS. The
UIKit editor and SwiftUI layers only build for iOS, so they need the simulator:

```bash
swift test

xcodebuild test -scheme rich-text-swift-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

Then format and lint:

```bash
swiftformat .
swiftlint
```

Some more guidelines:

- **Add tests.** A bug fix should come with a test that fails without it. HTML changes need a test
  that `decode(encode(x)) == x` still holds.
- **Check the editor by hand.** Unit tests force layout synchronously and can pass when the
  real app doesn't, so for anything that changes what the editor draws, check it in the Demo app.
  [`Demo/ManualTesting.md`](Demo/ManualTesting.md) covers paste and undo.
- **Respect the layers.** `RichTextCore` imports Foundation only, and UIKit stays in
  `Sources/RichTextEngine/UIKit`. CI checks this. See [Design](#design).
- **Document public API.** Every public symbol has a doc comment.
- **Benchmark performance work.** For a change that could affect parsing or typing speed, include
  `Scripts/benchmark diff main --markdown` output in the PR. See [Benchmarks](#benchmarks).
- **Keep pull requests focused.** One fix or feature per PR, with a description of what changed,
  why, and how you tested it. Link the issue it closes.

CI runs SwiftFormat and SwiftLint and the tests on macOS and the iOS simulator, checks the layer
boundaries, and builds the docs, the benchmarks and the Demo app. A pull request needs CI to pass and a maintainer's review before
it's merged.

By contributing, you agree that your contributions are licensed under the [MIT license](LICENSE).

## License

MIT. See [LICENSE](LICENSE).
