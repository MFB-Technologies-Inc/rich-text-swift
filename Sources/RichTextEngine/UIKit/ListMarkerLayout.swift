// ListMarkerLayout.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

#if canImport(UIKit)
    import RichTextCore
    import UIKit

    /// Every document block with a marker, plus its indent and marker
    /// attributes, as of the last `ListMarkerLayoutController.update`.
    ///
    /// Fragments share this rather than copying it. UIKit
    /// lays out an edit before the engine updates the markers, so TextKit can
    /// build a fragment against the old document and keep it afterwards. It
    /// also keeps the fragments of paragraphs an edit didn't touch, even when
    /// their offsets moved. A fragment that reads this when it draws is right
    /// either way.
    final class ListMarkerTable {
        var blocks: [DocumentBlock] = []
        var indents: [CGFloat] = []
        var attributes: [[NSAttributedString.Key: Any]] = []
    }

    /// A layout fragment that draws its list marker in the indent gutter.
    ///
    /// The marker is drawn, never stored: putting "• " in the
    /// document would corrupt the model, every selection offset, and the HTML.
    final class ListMarkerFragment: NSTextLayoutFragment {
        /// The markers to draw from, supplied by
        /// `ListMarkerLayoutController.makeFragment`. Which of this fragment's
        /// lines begin a block is only known once TextKit has broken it into
        /// line fragments, after it is constructed, so `lineMarkers` below
        /// resolves that lazily, on whatever access first follows layout.
        var table: ListMarkerTable?

        var blocks: [DocumentBlock] {
            table?.blocks ?? []
        }

        /// This fragment's document offset (UTF-16) as of now. TextKit keeps a
        /// fragment's range current as text before it changes, so this is
        /// read from that range rather than stored when the fragment is built.
        var fragmentStartOffset: Int {
            guard let layoutManager = textLayoutManager,
                  let documentStart = layoutManager.textContentManager?.documentRange.location
            else { return 0 }
            return layoutManager.offset(from: documentStart, to: rangeInElement.location)
        }

        /// A marker to draw for one line: its text, the gutter it is drawn
        /// into, and the attributes it is drawn with.
        struct LineMarker {
            var text: String
            var indent: CGFloat
            var attributes: [NSAttributedString.Key: Any]
        }

        /// One marker per line fragment that begins a block, keyed by that
        /// line's index into `textLineFragments`.
        ///
        /// "One layout fragment = one block" does not hold: TextKit does not
        /// give the document-final empty block a fragment of its own, instead
        /// placing it as a second `NSTextLineFragment` inside the *same*
        /// fragment as the preceding item. So a fragment can carry more than one
        /// marker — one per line that starts a block — rather than exactly one.
        var lineMarkers: [Int: LineMarker] {
            guard let table, !table.blocks.isEmpty else { return [:] }
            let blocks = table.blocks
            // Each line's document offset is this fragment's own start offset
            // plus that line's `characterRange.location` — relative to the
            // fragment's element, which here is exactly one paragraph, the same
            // one this fragment starts at.
            let lineStarts = textLineFragments.map { fragmentStartOffset + $0.characterRange.location }
            let markerTextByLine = ListMarkers.markers(forLineStartOffsets: lineStarts, blocks: blocks)
            var result: [Int: LineMarker] = [:]
            for (lineIndex, text) in markerTextByLine {
                guard let blockIndex = blocks.firstIndex(where: { $0.location == lineStarts[lineIndex] })
                else { continue }
                result[lineIndex] = LineMarker(
                    text: text,
                    indent: table.indents[blockIndex],
                    attributes: table.attributes[blockIndex]
                )
            }
            return result
        }

        /// Distance from the fragment's leading edge to the text, i.e. the
        /// gutter the marker is drawn into, for the fragment's first marked
        /// line. Kept for tests and call sites that only care about the common
        /// single-marker case.
        var indent: CGFloat {
            lineMarkers[lineMarkers.keys.min() ?? 0]?.indent ?? 0
        }

        /// The first marked line's marker text, for tests and call sites that
        /// only care about the common single-marker case.
        var marker: String? {
            lineMarkers[lineMarkers.keys.min() ?? 0]?.text
        }

        /// The first marked line's marker attributes (font/color).
        var markerAttributes: [NSAttributedString.Key: Any] {
            lineMarkers[lineMarkers.keys.min() ?? 0]?.attributes ?? [:]
        }

        /// Every marker's drawn text and the rectangle it occupies, both in the
        /// fragment-local coordinate system shared by `draw(at:in:)`'s `point`
        /// parameter and `renderingSurfaceBounds` (relative to
        /// `layoutFragmentFrame`, origin at its top-left). Empty when there is
        /// nothing to draw.
        ///
        /// Exposed (rather than kept private to `draw`) so tests can verify
        /// placement — including Fix 3's vertical alignment and Fix 4's
        /// no-clamping behavior — without inspecting drawn pixels.
        func markerLayouts() -> [(text: NSAttributedString, rect: CGRect)] {
            lineMarkers.keys.sorted().compactMap { lineIndex in
                markerLayout(atLineIndex: lineIndex)
            }
        }

        /// The first marked line's layout, for call sites that only care about
        /// the common single-marker case.
        func markerLayout() -> (text: NSAttributedString, rect: CGRect)? {
            guard let firstIndex = lineMarkers.keys.min() else { return nil }
            return markerLayout(atLineIndex: firstIndex)
        }

        private func markerLayout(atLineIndex lineIndex: Int) -> (text: NSAttributedString, rect: CGRect)? {
            guard let entry = lineMarkers[lineIndex], !entry.text.isEmpty,
                  lineIndex < textLineFragments.count
            else { return nil }
            let line = textLineFragments[lineIndex]
            let text = NSAttributedString(string: entry.text, attributes: entry.attributes)
            let size = text.size()
            // Right-align the marker against the text's *actual* leading edge —
            // not an assumed offset from the fragment's own origin. The
            // fragment's `layoutFragmentFrame` already starts at the paragraph's
            // head indent (measured: its origin.x sits `indent` points right of
            // the container's leading edge, while the first line fragment's
            // `typographicBounds.origin.x` is 0 in that same fragment-local
            // space) — so anchoring off `indent` here, as earlier code did,
            // double-counts it and draws the marker to the right of the text
            // instead of in the gutter to its left.
            //
            // Deliberately NOT clamped to 0 (Fix 4): a marker wider than the
            // gutter (e.g. "100." in a 24pt gutter) is left to extend further
            // left, past the fragment's own origin, rather than being crushed
            // flush against — or under — the text.
            let gap: CGFloat = 6
            let textLeadingEdge = line.typographicBounds.origin.x + line.glyphOrigin.x
            let originX = textLeadingEdge - gap - size.width
            let originY = markerY(for: size, line: line, attributes: entry.attributes)
            return (text, CGRect(x: originX, y: originY, width: size.width, height: size.height))
        }

        /// Vertical placement aligned to *its own* line fragment's baseline, not
        /// the whole (possibly multi-line) paragraph (Fix 3, generalized per
        /// line): centering on `layoutFragmentFrame.height` puts a first-line
        /// marker on line 2 of a wrapped item. Baseline alignment (rather than
        /// centering on the line's box) is used because the marker's font and
        /// the text's font can differ in size.
        private func markerY(
            for size: CGSize,
            line: NSTextLineFragment,
            attributes: [NSAttributedString.Key: Any]
        ) -> CGFloat {
            let font = attributes[.font] as? UIFont
            let ascent = font?.ascender ?? size.height
            // `typographicBounds.origin` is offset from the layout fragment's
            // own origin, and `glyphOrigin` is the leftmost glyph's baseline
            // within the line fragment's own coordinate system — together they
            // give the text's baseline in fragment-local coordinates.
            let baselineY = line.typographicBounds.origin.y + line.glyphOrigin.y
            return baselineY - ascent
        }

        override func draw(at point: CGPoint, in context: CGContext) {
            super.draw(at: point, in: context)
            let layouts = markerLayouts()
            guard !layouts.isEmpty else {
                return
            }
            UIGraphicsPushContext(context)
            for (text, rect) in layouts {
                text.draw(at: CGPoint(x: point.x + rect.origin.x, y: point.y + rect.origin.y))
            }
            UIGraphicsPopContext()
        }

        /// Backing-layer sizing and dirty rects are computed from this (its
        /// default is the union of line-fragment bounds), and every line fragment
        /// starts at `firstLineHeadIndent = indent` — so without this override the
        /// marker, which is drawn entirely inside the gutter before that indent,
        /// falls completely outside it and can be clipped or fail to invalidate on
        /// scroll (Fix 2). Unions **every** marker's rect (not just one) so the
        /// trailing case's second marker is not clipped either.
        override var renderingSurfaceBounds: CGRect {
            markerLayouts().reduce(super.renderingSurfaceBounds) { $0.union($1.rect) }
        }
    }

    /// Supplies the right marker for each layout fragment.
    ///
    /// It owns no rules: `ListMarkers` decides what each block's marker is, and
    /// `StyleResolver` decides how far the gutter extends. This only maps a
    /// fragment's location onto a block and hands the answer to the fragment.
    @MainActor
    final class ListMarkerLayoutController: NSObject, NSTextLayoutManagerDelegate {
        /// Shared with every fragment this builds. Marker font and color are
        /// resolved once here from each block's own kind/depth and the theme
        /// (Fix 5), rather than re-resolved per fragment from a fixed guess.
        private let table = ListMarkerTable()
        private var markers: [String?] = []
        private var theme: Theme = .default

        /// Recomputes markers for `text`. Call after every render **and** after
        /// every out-of-band edit (typing, pasting) that changes the document
        /// without going through `render(restoring:)` — see
        /// `UIKitEditorEngine.synchronizeFromTextView()`, which does both this
        /// and the layout invalidation that makes the new markers actually
        /// redraw. Also call whenever `pendingBlockStyle` itself can have changed
        /// with no text change at all — a caret move onto or off of an empty
        /// block (see `UIKitEditorEngine.refreshTypingAttributes()`).
        ///
        /// `selection` and `pendingBlockStyle` feed
        /// `BlockScanner.effectiveBlocks(of:selection:pendingBlockStyle:)`, the
        /// rendering-only substitution that lets a still-empty
        /// list item show its bullet/number immediately, before any character
        /// exists to carry the role in the document.
        func update(
            for text: AttributedString,
            theme: Theme,
            selection: TextSelection = .caret(at: 0),
            pendingBlockStyle: BlockStyle? = nil
        ) {
            self.theme = theme
            let blocks = BlockScanner.effectiveBlocks(
                of: text,
                selection: selection,
                pendingBlockStyle: pendingBlockStyle
            )
            table.blocks = blocks
            markers = ListMarkers.markers(for: blocks)
            table.indents = blocks.map { block in
                CGFloat(StyleResolver.resolve(block: block.style, typingAttributes: TypingAttributes(), theme: theme)
                    .headIndent)
            }
            table.attributes = blocks.map { block in
                let style = StyleResolver.resolve(
                    block: block.style,
                    typingAttributes: TypingAttributes(),
                    theme: theme
                )
                return [
                    NSAttributedString.Key.font: UIFont.systemFont(ofSize: style.fontSize),
                    NSAttributedString.Key.foregroundColor: style.foregroundColor
                        .map(UIKitRendering.uiColor(_:)) ?? UIColor.label,
                ]
            }
        }

        /// Installs `self` as the layout manager's marker source.
        ///
        /// - Important: `NSTextLayoutManager.delegate` is a **weak** reference —
        ///   this controller has no other owner, so it (and every marker it
        ///   draws) disappears the moment whatever holds it (the engine) is
        ///   deallocated, even if the text view itself lives on.
        /// - Important: this simply overwrites `textLayoutManager.delegate`. Any
        ///   delegate already installed there is silently replaced, not chained
        ///   or restored — call this before anything else claims the delegate,
        ///   and don't expect a second `install(on:)` (or a second controller) to
        ///   coexist with this one.
        func install(on textLayoutManager: NSTextLayoutManager) {
            textLayoutManager.delegate = self
        }

        /// The marker for the block containing `offset`, or nil.
        func marker(atUTF16Offset offset: Int) -> String? {
            guard let index = blockIndex(containing: offset) else { return nil }
            return markers[index]
        }

        private func blockIndex(containing offset: Int) -> Int? {
            guard offset >= 0 else { return nil }
            return table.blocks.firstIndex { $0.location <= offset && offset <= $0.location + $0.length }
        }

        // MARK: - NSTextLayoutManagerDelegate

        /// `NSTextLayoutManagerDelegate` does not isolate this requirement to the
        /// main actor, so a plain (non-`@preconcurrency`) conformance requires it
        /// `nonisolated`. Every other member of this controller — and everything
        /// `makeFragment` touches — is main-actor-only, so rather than suppress
        /// that mismatch, this asserts it: an off-main call traps loudly via
        /// `MainActor.assumeIsolated` instead of racing silently the way
        /// `@preconcurrency` would have let it (Fix 6).
        nonisolated func textLayoutManager(
            _ textLayoutManager: NSTextLayoutManager,
            textLayoutFragmentFor _: NSTextLocation,
            in textElement: NSTextElement
        ) -> NSTextLayoutFragment {
            // `MainActor.assumeIsolated<T>` requires `T: Sendable`, and none of
            // `NSTextLayoutFragment`/`NSTextLayoutManager`/`NSTextLocation`/
            // `NSTextElement` are (TextKit 2's types are explicitly marked
            // non-`Sendable`) — so neither the closure's return value nor its
            // captures can cross that generic boundary normally. `nonisolated
            // (unsafe)` on these bindings is the escape hatch: it asserts what
            // `assumeIsolated`'s runtime check already enforces — this all runs
            // on the main thread, synchronously, before this function returns —
            // rather than fighting the compiler's conservative region analysis
            // of a `nonisolated` function's parameters.
            nonisolated(unsafe) let layoutManager = textLayoutManager
            nonisolated(unsafe) let textElement = textElement
            nonisolated(unsafe) var fragment: NSTextLayoutFragment!
            MainActor.assumeIsolated {
                fragment = makeFragment(for: layoutManager, in: textElement)
            }
            return fragment
        }

        private func makeFragment(
            for textLayoutManager: NSTextLayoutManager,
            in textElement: NSTextElement
        ) -> NSTextLayoutFragment {
            let fragment = ListMarkerFragment(textElement: textElement, range: textElement.elementRange)
            // An empty document gets no marker. Its only
            // block can still carry a list role, from the item just deleted,
            // and a bullet there would sit over the placeholder.
            guard textLayoutManager.textContentManager?.documentRange.isEmpty == false else {
                return fragment
            }
            fragment.table = table
            return fragment
        }
    }
#endif
