// StyleResolverTests.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
import RichTextCore
@testable import RichTextEngine
import Testing

struct StyleResolverTests {
    private let red = RichTextColor(red: 255, green: 0, blue: 0)

    /// Builds the `TypingAttributes` a real caller would derive from `text`'s
    /// inline attributes, then resolves through the shipped
    /// `resolve(block:typingAttributes:theme:)` overload — the only one
    /// `StyleResolver` still exposes (the `slice:`-based overload was dead
    /// production code; the renderer always goes through `TypingAttributes`).
    private func resolve(_ text: AttributedString, block: BlockStyle = .paragraph) -> RenderedStyle {
        let slice = text[text.startIndex ..< text.endIndex]
        var typing = TypingAttributes()
        typing.bold = slice.bold == true
        typing.italic = slice.italic == true
        typing.underline = slice.underline == true
        typing.strikethrough = slice.strikethrough == true
        typing.textColor = slice.textColor
        return StyleResolver.resolve(block: block, typingAttributes: typing, theme: .default)
    }

    @Test func paragraphUsesTheThemeBodySize() {
        let style = resolve(Sem.block("abc"))
        #expect(style.fontSize == Theme.default.paragraph.fontSize)
        #expect(style.isBold == false)
        #expect(style.indentLevel == 0)
    }

    @Test func headingsUseTheirThemeAttributes() {
        #expect(resolve(Sem.block("T", .heading(1)), block: .heading(1)).fontSize == Theme.default.heading1.fontSize)
        #expect(resolve(Sem.block("T", .heading(2)), block: .heading(2)).fontSize == Theme.default.heading2.fontSize)
        #expect(resolve(Sem.block("T", .heading(3)), block: .heading(3)).fontSize == Theme.default.heading3.fontSize)
        // The theme makes headings bold even with no inline bold attribute.
        #expect(resolve(Sem.block("T", .heading(1)), block: .heading(1)).isBold)
    }

    @Test func inlineBoldAddsToAnUnboldTheme() {
        let style = resolve(Sem.with(Sem.block("abc"), bold: true))
        #expect(style.isBold)
        #expect(style.fontSize == Theme.default.paragraph.fontSize)
    }

    @Test func inlineBoldCannotUnboldAThemedHeading() {
        let heading = Sem.block("T", .heading(1))
        #expect(resolve(heading, block: .heading(1)).isBold)
    }

    @Test func inlineFlagsMapThrough() {
        let style = resolve(Sem.with(Sem.block("abc"), italic: true, underline: true, strikethrough: true))
        #expect(style.isItalic)
        #expect(style.isUnderlined)
        #expect(style.isStruckThrough)
    }

    @Test func inlineColorOverridesTheThemeColor() {
        #expect(resolve(Sem.with(Sem.block("abc"), color: red)).foregroundColor == red)
        // No inline color: fall back to whatever the theme specifies (nil in v1).
        #expect(resolve(Sem.block("abc")).foregroundColor == Theme.default.paragraph.foregroundColor)
    }

    @Test func listItemsCarryAnIndentLevelFromDepth() {
        #expect(resolve(Sem.block("i", .listItem(.unordered, depth: 0)), block: .listItem(.unordered, depth: 0))
            .indentLevel == 1)
        #expect(resolve(Sem.block("i", .listItem(.ordered, depth: 2)), block: .listItem(.ordered, depth: 2))
            .indentLevel == 3)
        #expect(resolve(Sem.block("i", .listItem(.unordered, depth: 0)), block: .listItem(.unordered, depth: 0))
            .fontSize == Theme.default.listItem.fontSize)
    }

    @Test func resolvingFromTypingAttributes() {
        var typing = TypingAttributes()
        typing.bold = true
        typing.textColor = red
        let style = StyleResolver.resolve(block: .heading(3), typingAttributes: typing, theme: .default)
        #expect(style.fontSize == Theme.default.heading3.fontSize)
        #expect(style.isBold)
        #expect(style.foregroundColor == red)
    }

    // MARK: - resolve(block: BlockStyle?, ...) (Fix 2)

    @Test func nilBlockResolvesIdenticallyToParagraph() {
        var typing = TypingAttributes()
        typing.bold = true
        typing.textColor = red
        let mixed = StyleResolver.resolve(block: nil, typingAttributes: typing, theme: .default)
        let paragraph = StyleResolver.resolve(block: .paragraph, typingAttributes: typing, theme: .default)
        #expect(mixed == paragraph)
    }

    @Test func nonNilBlockIsUnaffectedByTheOptionalOverload() {
        var typing = TypingAttributes()
        typing.italic = true
        let optionalBlock: BlockStyle? = .heading(2)
        let viaOptional = StyleResolver.resolve(block: optionalBlock, typingAttributes: typing, theme: .default)
        let direct = StyleResolver.resolve(block: .heading(2), typingAttributes: typing, theme: .default)
        #expect(viaOptional == direct)
    }

    // MARK: - headIndent (Theme.listIndent wiring)

    @Test func nonListBlockHasZeroHeadIndent() {
        #expect(resolve(Sem.block("abc")).headIndent == 0)
    }

    @Test func depthZeroListItemHeadIndentEqualsOneIndentUnit() {
        let style = resolve(Sem.block("i", .listItem(.unordered, depth: 0)), block: .listItem(.unordered, depth: 0))
        #expect(style.headIndent == 24)
    }

    @Test func depthTwoListItemHeadIndentEqualsThreeIndentUnits() {
        let style = resolve(Sem.block("i", .listItem(.ordered, depth: 2)), block: .listItem(.ordered, depth: 2))
        #expect(style.headIndent == 72)
    }

    @Test func headIndentScalesWithACustomThemeListIndent() {
        let customTheme = Theme(
            paragraph: Theme.default.paragraph,
            heading1: Theme.default.heading1,
            heading2: Theme.default.heading2,
            heading3: Theme.default.heading3,
            listItem: Theme.default.listItem,
            blockquote: Theme.default.blockquote,
            listIndent: 10,
            blockquoteIndent: Theme.default.blockquoteIndent
        )
        let style = StyleResolver.resolve(
            block: .listItem(.unordered, depth: 2),
            typingAttributes: TypingAttributes(),
            theme: customTheme
        )
        #expect(style.headIndent == 30)
    }

    // MARK: - Blockquote (F5)

    @Test func blockquoteUsesItsOwnThemeAttributesNotParagraphs() {
        let style = resolve(Sem.block("q", .blockquote), block: .blockquote)
        #expect(style.foregroundColor == Theme.default.blockquote.foregroundColor)
        #expect(style.foregroundColor != Theme.default.paragraph.foregroundColor)
        #expect(style.fontSize == Theme.default.blockquote.fontSize)
    }

    @Test func blockquoteIndentsByTheThemesBlockquoteIndent() {
        let style = resolve(Sem.block("q", .blockquote), block: .blockquote)
        #expect(style.indentLevel == 1)
        #expect(style.headIndent == Theme.default.blockquoteIndent)
        // Not the list indent path: a quote is one fixed step, not a depth.
        #expect(resolve(Sem.block("q"), block: .paragraph).headIndent == 0)
    }

    @Test func anInlineColorOverridesTheBlockquoteThemeColor() {
        let style = resolve(Sem.with(Sem.block("q", .blockquote), color: red), block: .blockquote)
        #expect(style.foregroundColor == red)
    }
}
