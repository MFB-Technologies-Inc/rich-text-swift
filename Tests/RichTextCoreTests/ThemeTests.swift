// ThemeTests.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

@testable import RichTextCore
import Testing

struct ThemeTests {
    @Test func defaultHeadingsDescendInSize() {
        let t = Theme.default
        let h1 = t.attributes(for: .heading(1)).fontSize
        let h2 = t.attributes(for: .heading(2)).fontSize
        let h3 = t.attributes(for: .heading(3)).fontSize
        #expect(h1 > h2)
        #expect(h2 > h3)
    }

    @Test func defaultHeadingsAreBoldBodyIsNot() {
        let t = Theme.default
        #expect(t.attributes(for: .heading(1)).isBold == true)
        #expect(t.attributes(for: .paragraph).isBold == false)
    }

    @Test func listItemUsesBodySize() {
        let t = Theme.default
        #expect(t.attributes(for: .listItem(.unordered, depth: 0)).fontSize
            == t.attributes(for: .paragraph).fontSize)
    }

    @Test func headingLevelsOutsideOneToThreeClampToH3() {
        let t = Theme.default
        #expect(t.attributes(for: .heading(9)) == t.attributes(for: .heading(3)))
        #expect(t.attributes(for: .heading(0)) == t.attributes(for: .heading(3)))
    }

    @Test func themeIsValueEquatable() {
        #expect(Theme.default == Theme.default)
    }

    @Test func defaultListIndentIsTwentyFourPoints() {
        #expect(Theme.default.listIndent == 24)
    }

    // MARK: - Blockquote (F5)

    @Test func blockquoteResolvesToItsOwnAttributesNotParagraphs() {
        let t = Theme.default
        // The point of the assertion: `attributes(for: .blockquote)` must not
        // fall through to the paragraph entry. If blockquote were ever wired
        // to `return paragraph`, this fails.
        #expect(t.attributes(for: .blockquote) != t.attributes(for: .paragraph))
        #expect(t.attributes(for: .blockquote).foregroundColor != nil)
        #expect(t.attributes(for: .blockquote).foregroundColor != t.paragraph.foregroundColor)
    }

    @Test func blockquoteKeepsBodyTextSizeAndWeight() {
        let t = Theme.default
        #expect(t.attributes(for: .blockquote).fontSize == t.paragraph.fontSize)
        #expect(t.attributes(for: .blockquote).isBold == false)
    }

    @Test func defaultBlockquoteIndentIsTwentyFourPoints() {
        #expect(Theme.default.blockquoteIndent == 24)
    }
}
