// RichTextEditor.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

#if os(iOS)
    import RichTextCore
    import SwiftUI

    /// A native, `AttributedString`-backed rich text editor.
    ///
    /// ```swift
    /// @State private var document = AttributedString("Hello")
    ///
    /// var body: some View {
    ///     RichTextEditor(text: $document)
    /// }
    /// ```
    ///
    /// HTML is not the currency here: convert at your save/load boundary with
    /// `RichTextHTML.encode(_:)` / `RichTextHTML.decode(_:)`,
    /// so serialization cost is never paid on the keystroke path.
    public struct RichTextEditor: View {
        @Binding private var text: AttributedString
        /// `.environment(_:)` only scopes a value to the view it's applied to
        /// and *that view's descendants*. The intended toolbar usage —
        /// `RichTextEditor(text: $doc).richTextToolbar([...])` — puts the
        /// toolbar modifier *above* this view in the hierarchy, so this type
        /// cannot push a model down to it; only a wrapper the toolbar modifier
        /// creates and injects downward, wrapping `RichTextEditor`, can. So this
        /// view instead reads an optional model from the environment (the one
        /// such a wrapper will supply) and falls back to owning its own when
        /// nothing injected one (the plain `RichTextEditor(text: $doc)` case).
        @Environment(RichTextEditorModel.self) private var injectedModel: RichTextEditorModel?
        @State private var ownModel = RichTextEditorModel()
        private var model: RichTextEditorModel {
            injectedModel ?? ownModel
        }

        private let isEditable: Bool
        private let placeholder: String?
        private let pasteAsPlainText: Bool

        /// - Parameters:
        ///   - isEditable: `false` renders the document read-only: typing and
        ///     selection edits are refused by the text view, and the toolbar
        ///     disables its controls. Defaults to `true`.
        ///   - placeholder: Shown while the document has no characters. Drawn as
        ///     an overlay, never inserted into the document — placeholder text in
        ///     the document would appear in `RichTextHTML.encode` output, shift
        ///     every selection offset, and be deletable by the user.
        ///   - pasteAsPlainText: `true` strips all formatting from pasted
        ///     content, inserting it as plain text that adopts the caret's own
        ///     block role and inline state. Off by default. The default decodes
        ///     the pasteboard's HTML, so bold, italic, headings and lists
        ///     survive and are drawn in the editor's own theme; a source with no
        ///     HTML pastes as plain text. With the option on, a pasteboard
        ///     holding no text at all (an image, say) inserts nothing.
        public init(
            text: Binding<AttributedString>,
            isEditable: Bool = true,
            placeholder: String? = nil,
            pasteAsPlainText: Bool = false
        ) {
            _text = text
            self.isEditable = isEditable
            self.placeholder = placeholder
            self.pasteAsPlainText = pasteAsPlainText
        }

        /// Whether the placeholder should be visible for a given document.
        ///
        /// Pure and internal so the rule is testable without a rendered view: it
        /// shows only when there is a placeholder to show and the document has no
        /// characters at all. A document holding just a newline is *not* empty —
        /// it has a block the user can type into. A list turned on in an empty
        /// document (`blockStyle`, the caret's role) has started, so the
        /// placeholder gives way to it.
        static func showsPlaceholder(
            placeholder: String?,
            in text: AttributedString,
            blockStyle: BlockStyle? = nil
        ) -> Bool {
            guard let placeholder, !placeholder.isEmpty else { return false }
            if case .listItem = blockStyle {
                return false
            }
            return text.characters.isEmpty
        }

        public var body: some View {
            RichTextEditorRepresentable(
                text: $text,
                model: model,
                isEditable: isEditable,
                pasteAsPlainText: pasteAsPlainText
            )
            .overlay(alignment: .topLeading) {
                if Self.showsPlaceholder(placeholder: placeholder, in: text, blockStyle: model.formatState.blockStyle) {
                    Text(placeholder ?? "")
                        .font(.system(size: RichTextEditorRepresentable.bodyFontSize))
                        .foregroundStyle(.placeholder)
                        // Lines the placeholder up with where the text view
                        // actually draws its first glyph: the container inset
                        // plus the text container's line-fragment padding.
                        .padding(.leading, RichTextEditorRepresentable.textLeadingInset)
                        .padding(.top, RichTextEditorRepresentable.textTopInset)
                        // Taps belong to the text view underneath.
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        }
    }
#endif
