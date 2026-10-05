// UIKitRendering.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

#if canImport(UIKit)
    import RichTextCore
    import UIKit

    /// Translates between the semantic `AttributedString` the engine owns and the
    /// `NSAttributedString` `UITextView.textStorage` needs.
    ///
    /// Deliberately mechanical: every *decision* (what a heading looks like, what a
    /// command does) is made in the UIKit-free core, so the only thing that can go
    /// wrong here is translation, which M4's integration exercises directly.
    /// The semantic custom attributes are copied into the NSAttributedString under
    /// their `CodableAttributedStringKey.name`s so they survive typing, cut/paste,
    /// and are readable on the way back out.
    enum UIKitRendering {
        // MARK: - Semantic -> rendered

        /// Builds the `NSAttributedString` `UITextView.textStorage` needs: the
        /// semantic attributes come verbatim from `SemanticNSBridge` (single
        /// source of truth for that mapping — round-trip tested), and this layer
        /// only *adds* rendering attributes (font, color, underline/strikethrough,
        /// paragraph indentation) on top, deciding nothing about what the
        /// semantic document says.
        static func nsAttributedString(
            from text: AttributedString,
            theme: Theme,
            selection: TextSelection,
            pendingBlockStyle: BlockStyle?
        ) -> NSAttributedString {
            let output = NSMutableAttributedString(attributedString: SemanticNSBridge.nsAttributedString(from: text))

            // `BlockScanner.effectiveBlocks(of:selection:pendingBlockStyle:)` is
            // the tested, authoritative source for each block's role, including
            // the rendering-only substitution of a pending block style (M3
            // decision D13) onto the caret's own empty block — never infer a
            // role from a run's own `blockStyle` attribute here. Measured: the
            // write path (`SemanticNSBridge.nsAttributedString`) emits a lone
            // "\n" run with an *entirely empty* attribute dictionary whenever a
            // block's inline attributes differ from what flanks its terminating
            // newline, which happens for any styled heading/list item whose text
            // isn't uniformly attributed straight through the newline. Inferring
            // `.paragraph` for that run (the previous behavior) rendered that
            // block's own terminator at paragraph size and zero indent.
            // `BlockScanner`'s offsets are UTF-16, the same currency `NSRange`
            // uses, so they're used directly — no index conversion needed.
            for block in BlockScanner.effectiveBlocks(
                of: text,
                selection: selection,
                pendingBlockStyle: pendingBlockStyle
            ) {
                let blockRange = NSRange(location: block.location, length: block.length)
                applyRenderingAttributes(to: output, in: blockRange, blockStyle: block.style, theme: theme)

                // The block's trailing separator "\n" (if any — the last block
                // has none) renders with the same role as the block it closes,
                // so a heading's or list item's terminator shares its metrics
                // rather than falling back to paragraph size/indent.
                let separatorLocation = block.location + block.length
                if separatorLocation < output.length {
                    applyRenderingAttributes(
                        to: output,
                        in: NSRange(location: separatorLocation, length: 1),
                        blockStyle: block.style,
                        theme: theme
                    )
                }
            }
            return output
        }

        /// Applies rendering attributes across `range`, resolving each run's
        /// inline flags/color from the semantic attributes already present in
        /// `output` (from `SemanticNSBridge`) but resolving the *block* role from
        /// the caller-supplied `blockStyle` rather than any attribute on the run.
        private static func applyRenderingAttributes(
            to output: NSMutableAttributedString,
            in range: NSRange,
            blockStyle: BlockStyle,
            theme: Theme
        ) {
            guard range.length > 0 else {
                return
            }
            output.enumerateAttributes(in: range) { semantic, subrange, _ in
                // `typingAttributes(from:)`'s `blockStyle` field is simply
                // ignored below — `StyleResolver.resolve(block:...)` takes the
                // caller-supplied `blockStyle` explicitly, never the one on
                // `typingAttributes`.
                let typingAttributes = SemanticNSBridge.typingAttributes(from: semantic)
                let style = StyleResolver.resolve(block: blockStyle, typingAttributes: typingAttributes, theme: theme)
                output.addAttributes(attributes(for: style, semantic: semantic), range: subrange)
            }
        }

        /// The visual attributes for a resolved style, merged with the semantic
        /// attributes that must ride along in storage.
        static func attributes(
            for style: RenderedStyle,
            semantic: [NSAttributedString.Key: Any]
        ) -> [NSAttributedString.Key: Any] {
            var traits = UIFontDescriptor.SymbolicTraits()
            if style.isBold {
                traits.insert(.traitBold)
            }
            if style.isItalic {
                traits.insert(.traitItalic)
            }
            let base = UIFont.systemFont(ofSize: style.fontSize)
            let font = base.fontDescriptor.withSymbolicTraits(traits)
                .map { UIFont(descriptor: $0, size: style.fontSize) } ?? base

            var attributes: [NSAttributedString.Key: Any] = semantic
            attributes[.font] = font
            // `UIColor.label` is a platform default for when the theme expresses
            // no foreground color (v1's `Theme` has no "default text color"
            // concept) — adding that to `Theme` is deferred (post-v1/M4 backlog).
            attributes[.foregroundColor] = style.foregroundColor.map(uiColor(_:)) ?? UIColor.label
            // `.single` is a platform default line style; `Theme` has no concept
            // of underline/strikethrough style (thick, double, color, etc.) to
            // express instead — deferred, same as above.
            if style.isUnderlined {
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            if style.isStruckThrough {
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
            if style.indentLevel > 0 {
                let paragraph = NSMutableParagraphStyle()
                let indent = CGFloat(style.headIndent)
                paragraph.firstLineHeadIndent = indent
                paragraph.headIndent = indent
                attributes[.paragraphStyle] = paragraph
            }
            return attributes
        }

        // MARK: - Rendered -> semantic

        /// Reads the semantic document back out of storage, dropping every
        /// rendering attribute. Font size is never consulted — the marker is the
        /// source of truth (dev-plan §6a). Delegates to `SemanticNSBridge` so
        /// there is exactly one implementation of the semantic mapping.
        static func semanticAttributedString(from storage: NSAttributedString) -> AttributedString {
            SemanticNSBridge.attributedString(from: storage)
        }

        // MARK: - Helpers

        static func uiColor(_ color: RichTextColor) -> UIColor {
            UIColor(
                red: CGFloat(color.red) / 255,
                green: CGFloat(color.green) / 255,
                blue: CGFloat(color.blue) / 255,
                alpha: 1
            )
        }
    }
#endif
