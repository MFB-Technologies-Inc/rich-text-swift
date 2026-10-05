// HTMLDecoderBuilder.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation

extension HTMLDecoder {
    struct Builder {
        /// Finalized blocks, each already carrying its `blockStyle` marker.
        var blocks: [Block] = []
        /// Content of the block currently being built.
        var pendingRuns: [Run] = []
        /// Whether a block (explicit element or implicit paragraph) is open.
        var inBlock = false
        var currentStyle: BlockStyle = .paragraph
        /// Active inline formatting frames; each end tag pops the nearest match.
        var inlineStack: [(tag: String, delta: (inout InlineState) -> Void)] = []
        /// Enclosing `ul`/`ol` containers, used to tag `li` blocks.
        var listStack: [ListKind] = []
        /// Non-nil while inside an element whose text content is machine data
        /// (`<style>`, `<script>`, `<head>`, …). Depth-counted so a nested tag
        /// of the same name does not end the region early.
        var skipTag: String?
        var skipDepth = 0

        // MARK: - Token dispatch

        mutating func consume(_ token: HTMLToken) {
            // Inside a skip region nothing produces content; we only track
            // nesting so we know where the region ends.
            if let skipTag {
                switch token {
                case let .startTag(name, _, selfClosing):
                    // A void element never nests, so it cannot deepen the region.
                    if name == skipTag, !selfClosing, !HTMLTagClasses.void.contains(name) {
                        skipDepth += 1
                    }
                case let .endTag(name):
                    if name == skipTag {
                        skipDepth -= 1
                        if skipDepth == 0 {
                            self.skipTag = nil
                        }
                    }
                case .text:
                    break
                }
                return
            }
            switch token {
            case let .text(text):
                appendText(text)
            case let .startTag(name, attributes, selfClosing):
                handleStart(name, attributes, selfClosing)
            case let .endTag(name):
                handleEnd(name)
            }
        }

        mutating func handleStart(_ name: String, _ attributes: [String: String], _ selfClosing: Bool) {
            if handleContentlessStart(name, attributes, selfClosing) {
                return
            }
            if openBlockElement(name) {
                return
            }
            openInlineElement(name, attributes)
        }

        /// Handles the start tags that never open a block or an inline frame:
        /// `<br>`, `<hr>`, skipped machine-data elements, `<img>`, and any
        /// other self-closing tag. Returns true when `name` was one of them
        /// and the tag is fully dealt with.
        mutating func handleContentlessStart(
            _ name: String,
            _ attributes: [String: String],
            _ selfClosing: Bool
        ) -> Bool {
            // <br> becomes a soft line break in the current block.
            if name == "br" {
                ensureBlock()
                pendingRuns.append(Run(text: String(RichTextHTML.softLineBreak), state: activeState()))
                return true
            }
            // <hr> is semantically block-level despite being void (no content,
            // no end tag): close whatever block is open so surrounding text
            // does not get jammed together, without opening a fresh block of
            // its own (which would leave a stray empty paragraph when <hr> is
            // the first or last thing in the document).
            if name == "hr" {
                closeBlock()
                return true
            }
            // Machine-data elements: suppress their content entirely rather
            // than unwrapping it. Void elements are excluded — they have no
            // end tag, so opening a region on one would never close.
            if HTMLTagClasses.skipContent.contains(name),
               !selfClosing,
               !HTMLTagClasses.void.contains(name)
            {
                skipTag = name
                skipDepth = 1
                return true
            }
            // <img> is a v1 deferral, but dropping it without a trace loses
            // content irrecoverably. Alt text is the one human-meaningful part
            // we can keep.
            if name == "img" {
                if let alt = attributes["alt"], !alt.isEmpty {
                    ensureBlock()
                    pendingRuns.append(Run(text: alt, state: activeState()))
                }
                return true
            }
            // Other void / self-closing tags carry no content and no end tag.
            return selfClosing
        }

        /// Opens the block a block-level start tag calls for, or updates the
        /// list stack. Returns false when `name` is not one of these tags.
        mutating func openBlockElement(_ name: String) -> Bool {
            switch name {
            case "p":
                openBlock(.paragraph)
            case "h1":
                openBlock(.heading(1))
            case "h2":
                openBlock(.heading(2))
            case "h3":
                openBlock(.heading(3))
            // Explicitly handled rather than left to the unknown-block
            // fallback in `openInlineElement`, which would open a `.paragraph`
            // and lose the quote. Nesting flattens: a second `<blockquote>`
            // inside the first reuses the (still empty) open block via
            // `openBlock`'s wrapper rule, and `.blockquote` carries no depth
            // to record it.
            //
            // KNOWN LIMITATION (GitHub issue #20): there is no quote-context
            // stack here, so a `<blockquote>` wrapping *multiple* blocks only
            // keeps the quote role on the first one — `<blockquote><p>a</p>
            // <p>b</p></blockquote>` decodes `b` as a plain `.paragraph`,
            // because nothing records that a quote is still open once the
            // inner `<p>` opens its own block.
            case "blockquote":
                openBlock(.blockquote)
            case "li":
                let kind = listStack.last ?? .unordered
                let depth = max(0, listStack.count - 1)
                openBlock(.listItem(kind, depth: depth))
            case "ul":
                listStack.append(.unordered)
            case "ol":
                listStack.append(.ordered)
            default:
                return false
            }
            return true
        }

        /// Pushes the inline frame a start tag calls for. Unknown block-level
        /// tags open a paragraph; unknown inline tags are unwrapped.
        mutating func openInlineElement(_ name: String, _ attributes: [String: String]) {
            if let delta = Builder.inlineDelta(for: name) {
                pushInline(name, delta)
                return
            }
            // `<font color>` is what WebKit's `foreColor` emits with
            // `styleWithCSS` off, and what Outlook pastes; it is import-only
            // (the encoder always writes `<span style>`). An inline `style`
            // color outranks the presentational attribute, as in CSS.
            if name == "span" || name == "font" {
                // Black is the absence of a text color everywhere in the
                // system (`RichTextColor.black`): `HTMLColor` parses
                // `#000000`/`black`/`rgb(0,0,0)`/etc. to RGB(0,0,0), and the
                // decoder normalizes it to *no* color here — which must clear
                // an inherited color, not merely skip assigning one, or
                // `<span red>a<span black>b</span></span>` would decode `b`
                // red. An absent or unparseable color still inherits.
                let color = HTMLColor.colorFromStyle(attributes["style"] ?? "")
                    ?? (name == "font" ? attributes["color"].flatMap(HTMLColor.parse) : nil)
                pushInline(name) { state in
                    if let color {
                        state.color = color == .black ? nil : color
                    }
                }
                return
            }
            if HTMLTagClasses.isBlockLevel(name) {
                // Unknown-but-block-level: open a paragraph boundary the
                // way <p> does. Failing safe — see HTMLTagClasses.
                openBlock(.paragraph)
            } else {
                // Known inline: unwrap. Keep its text, drop its formatting,
                // and do not disturb the block.
                pushInline(name) { _ in }
            }
        }

        /// The inline formatting an inline tag folds into `InlineState`, or
        /// `nil` when `name` is not one of them. `strong`/`em` are the
        /// semantic spellings of `b`/`i`. `ins` is the underline tag in the
        /// draft-js/Lexical dialect, the way `del` is its strikethrough:
        /// editors in that family are a common source of imported HTML, and
        /// dropping `ins` silently loses every underline they wrote.
        static func inlineDelta(for name: String) -> ((inout InlineState) -> Void)? {
            switch name {
            case "b", "strong":
                { $0.bold = true }
            case "i", "em":
                { $0.italic = true }
            case "u", "ins":
                { $0.underline = true }
            case "s", "strike", "del":
                { $0.strikethrough = true }
            default:
                nil
            }
        }

        mutating func handleEnd(_ name: String) {
            switch name {
            case "p", "h1", "h2", "h3", "li", "blockquote":
                closeBlock()
            case "ul", "ol":
                closeBlock()
                if !listStack.isEmpty {
                    listStack.removeLast()
                }
            default:
                if HTMLTagClasses.isBlockLevel(name) {
                    closeBlock()
                } else {
                    // Inline or unknown: pop the nearest matching frame; ignore
                    // a stray close with no match.
                    popInline(name)
                }
            }
        }

        // MARK: - Inline stack

        mutating func pushInline(_ tag: String, _ delta: @escaping (inout InlineState) -> Void) {
            inlineStack.append((tag, delta))
        }

        mutating func popInline(_ tag: String) {
            if let idx = inlineStack.lastIndex(where: { $0.tag == tag }) {
                inlineStack.remove(at: idx)
            }
        }

        func activeState() -> InlineState {
            var state = InlineState()
            for frame in inlineStack {
                frame.delta(&state)
            }
            return state
        }

        // MARK: - Block lifecycle

        mutating func ensureBlock() {
            if !inBlock {
                inBlock = true
                currentStyle = .paragraph
                pendingRuns = []
            }
        }

        /// Opens a block boundary.
        ///
        /// When a block is already open but still empty — or holds only
        /// whitespace, as happens between pretty-printed wrapper tags like
        /// `<div>\n  <p>` — that block is a wrapper (`<html>`, `<body>`,
        /// `<div>`, or an `<li>` that immediately contains a `<p>`) rather
        /// than content: reuse it instead of finalizing an empty block. An
        /// explicitly closed empty block — `<p></p>` — has already been
        /// finalized by the time we get here, so deliberate blank paragraphs
        /// are unaffected. Trade-off: a whitespace-only block that was never
        /// explicitly closed (e.g. `<p>a<p> <p>b`) is swallowed into the next
        /// block rather than surviving as a blank middle block the way a
        /// browser would render it — accepted because the corpus's real
        /// blank-line idioms are always explicitly closed (`<div><br></div>`,
        /// `<p></p>`).
        mutating func openBlock(_ style: BlockStyle) {
            if inBlock, !pendingRuns.contains(where: { containsContent($0.text) }) {
                // Keep whichever role is more specific, per `specificity(of:)`
                // — e.g. a <p> inside an <li> must not demote the block to a
                // paragraph, and list membership must survive a nested
                // <blockquote> or heading (D-BQ2) regardless of tag order.
                if HTMLDecoder.specificity(of: style) > HTMLDecoder.specificity(of: currentStyle) {
                    currentStyle = style
                } else if case .listItem = style, case .listItem = currentStyle {
                    // An `<li>` holding nothing but a nested list is the
                    // placeholder `HTMLEncoder` opens for a skipped level
                    // (GitHub issue #49): the inner item's kind and depth are
                    // the real ones, so they win over the placeholder's.
                    currentStyle = style
                }
                // Discard the pending whitespace — it was inter-tag padding,
                // not content, and must not leak into the reused block.
                pendingRuns = []
                return
            }
            if inBlock {
                finalizeBlock()
            }
            inBlock = true
            currentStyle = style
            pendingRuns = []
        }

        mutating func closeBlock() {
            if inBlock {
                finalizeBlock()
            }
        }

        mutating func appendText(_ text: String) {
            // Whitespace-only text outside any block is inter-element padding.
            guard inBlock || containsContent(text) else {
                return
            }
            ensureBlock()
            pendingRuns.append(Run(text: text, state: activeState()))
        }

        /// Collapse whitespace, trim block edges, apply inline attributes, and
        /// stamp the block marker; then append to `blocks`.
        mutating func finalizeBlock() {
            blocks.append(Builder.buildBlock(pendingRuns, style: currentStyle))
            pendingRuns = []
            inBlock = false
        }

        mutating func finish() -> AttributedString {
            if inBlock {
                finalizeBlock()
            }
            // Assemble the plain text first, then apply attributes by range.
            // Appending one `AttributedString` per run costs a Foundation
            // splice, plus paragraph fixing, for every run.
            var text = ""
            for (index, block) in blocks.enumerated() {
                if index > 0 {
                    text += "\n"
                }
                for run in block.runs {
                    text += run.text
                }
            }
            // Walk by unicode scalars, not characters: a run can begin with a
            // combining mark that joins the previous run's last character, and
            // attribute boundaries must stay where `+=` would have put them.
            var result = AttributedString(text)
            var start = result.startIndex
            for (index, block) in blocks.enumerated() {
                if index > 0 {
                    start = result.unicodeScalars.index(after: start)
                }
                let blockStart = start
                for run in block.runs {
                    let end = result.unicodeScalars.index(start, offsetBy: run.text.unicodeScalars.count)
                    if run.attributes != AttributeContainer() {
                        result[start ..< end].setAttributes(run.attributes)
                    }
                    start = end
                }
                // `blockStyle` is paragraph-bounded, so set it once for the
                // whole block, not once per run. An empty block has nothing to
                // carry it: Foundation's AttributedString can't attach an
                // attribute to a zero-length range, so an empty styled block
                // (e.g. `<h1></h1>`) round-trips as `.paragraph`. Known v1
                // limitation; revisit in M3 (may need a zero-width sentinel in
                // the engine). See also HTMLEncoder.splitBlocks(_:).
                if blockStart < start {
                    result[blockStart ..< start].blockStyle = block.style
                }
            }
            return result
        }
    }
}
