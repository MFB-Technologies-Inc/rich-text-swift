// FormatPanelControl.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

#if os(iOS)
    import RichTextCore
    import RichTextEngine
    import SwiftUI

    /// The `.format` control: one 44pt "Aa" button that opens a popover of
    /// paragraph styles (body text and every heading level) and text color,
    /// the way Notes and Pages group them.
    ///
    /// Moving those out of the bar keeps `.html` to seven controls, which fit a
    /// phone's width without scrolling at the toolbar's 44pt target size even
    /// when the host pads the editor. One button per heading level pushed the
    /// last controls off-screen.
    ///
    /// A style row sets a role rather than toggling one: picking the style the
    /// selection already has leaves it alone, and "Body" is how the user goes
    /// back to a paragraph. That matches how a list with a checkmark reads,
    /// where the separate `.heading(_:)` buttons keep their toggle behavior.
    /// The popover stays open after a pick so the user can also set a color.
    struct FormatPanelControl: View {
        let model: RichTextEditorModel
        let isActive: Bool

        @State private var isPresented = false

        /// One paragraph-style row in the panel.
        enum Style: Hashable, CaseIterable {
            case body
            case heading(HeadingLevel)

            static var allCases: [Style] {
                [.body] + HeadingLevel.allCases.map(Style.heading)
            }

            var blockStyle: BlockStyle {
                switch self {
                case .body: .paragraph
                case let .heading(level): .heading(level.rawValue)
                }
            }

            var title: String {
                switch self {
                case .body: "Body"
                case let .heading(level): RichTextControl.heading(level).accessibilityLabel
                }
            }

            /// How the editor draws this style, so each row previews it. The
            /// editor always uses `Theme.default` until theming is public.
            var appearance: Theme.BlockAttributes {
                let theme = Theme.default
                return switch self {
                case .body: theme.paragraph
                case .heading(.h1): theme.heading1
                case .heading(.h2): theme.heading2
                case .heading(.h3): theme.heading3
                }
            }
        }

        /// Applies a style to every block the selection touches. The tested
        /// seam, since swift-testing cannot tap inside a SwiftUI popover.
        func select(_ style: Style) {
            guard model.isEditable else {
                return
            }
            model.apply(.setBlockStyle(style.blockStyle))
        }

        /// Whether the panel shows a checkmark next to `style`. Nothing is
        /// checked for a list item or a selection spanning differing roles,
        /// since no single row describes it.
        func isChecked(_ style: Style) -> Bool {
            model.formatState.blockStyle == style.blockStyle
        }

        var body: some View {
            Button {
                isPresented = true
            } label: {
                Image(systemName: RichTextControl.format.systemImage ?? "")
                    .font(.system(size: 17, weight: .medium))
                    .toolbarControlChrome(active: isActive)
            }
            .buttonStyle(.plain)
            .disabled(!model.isEditable)
            .accessibilityLabel(RichTextControl.format.accessibilityLabel)
            .accessibilityIdentifier(RichTextControl.format.accessibilityLabel)
            .accessibilityAddTraits(isActive ? [.isSelected] : [])
            .popover(isPresented: $isPresented) {
                panel
                    // A popover on iPhone too, not a full sheet: the user keeps
                    // sight of the text they are styling.
                    .presentationCompactAdaptation(.popover)
            }
        }

        private var panel: some View {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Style.allCases, id: \.self) { style in
                    styleRow(style)
                }
                Divider()
                    .padding(.vertical, 4)
                HStack {
                    Text("Color")
                    Spacer()
                    TextColorControl(
                        model: model,
                        isActive: RichTextControl.textColor.isActive(in: model.formatState)
                    )
                }
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 8)
            .frame(width: 260)
        }

        private func styleRow(_ style: Style) -> some View {
            let checked = isChecked(style)
            return Button {
                select(style)
            } label: {
                HStack {
                    Text(style.title)
                        .font(.system(
                            size: style.appearance.fontSize,
                            weight: style.appearance.isBold ? .bold : .regular
                        ))
                        .foregroundStyle(Color.primary)
                    Spacer()
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                        .opacity(checked ? 1 : 0)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!model.isEditable)
            .accessibilityAddTraits(checked ? [.isSelected] : [])
        }
    }
#endif
