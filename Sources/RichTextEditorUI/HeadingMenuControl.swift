// HeadingMenuControl.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

#if os(iOS)
    import RichTextCore
    import RichTextEngine
    import SwiftUI

    /// The `.headings` control: one 44pt button that opens a menu of body text
    /// and every heading level.
    ///
    /// Grouping the levels keeps `.html` to eight controls, which fit a phone's
    /// width without scrolling at the toolbar's 44pt target size. One button
    /// per level pushed the last levels off-screen.
    ///
    /// The menu sets a role rather than toggling one: picking the level the
    /// selection already has leaves it alone, and "Body" is how the user goes
    /// back to a paragraph. That matches how a menu with a checkmark reads,
    /// where the separate `.heading(_:)` buttons keep their toggle behavior.
    struct HeadingMenuControl: View {
        let model: RichTextEditorModel
        let isActive: Bool

        /// One entry in the menu.
        enum Choice: Hashable, CaseIterable {
            case body
            case heading(HeadingLevel)

            static var allCases: [Choice] {
                [.body] + HeadingLevel.allCases.map(Choice.heading)
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
        }

        /// Applies a menu choice to every block the selection touches. The
        /// tested seam, since swift-testing cannot open a SwiftUI menu.
        func select(_ choice: Choice) {
            guard model.isEditable else {
                return
            }
            model.apply(.setBlockStyle(choice.blockStyle))
        }

        /// Whether the menu shows a checkmark next to `choice`. Nothing is
        /// checked for a list item or a selection spanning differing roles,
        /// since no single entry describes it.
        func isChecked(_ choice: Choice) -> Bool {
            model.formatState.blockStyle == choice.blockStyle
        }

        /// The button's label: the selected heading's level, or the resting
        /// "H" outside a heading.
        var labelText: String {
            let level = RichTextControl.activeHeadingLevel(in: model.formatState)
            return level.flatMap { RichTextControl.heading($0).textLabel }
                ?? RichTextControl.headings.textLabel ?? ""
        }

        var body: some View {
            Menu {
                ForEach(Choice.allCases, id: \.self) { choice in
                    Button {
                        select(choice)
                    } label: {
                        if isChecked(choice) {
                            Label(choice.title, systemImage: "checkmark")
                        } else {
                            Text(choice.title)
                        }
                    }
                }
            } label: {
                Text(labelText)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .toolbarControlChrome(active: isActive)
            }
            .buttonStyle(.plain)
            .disabled(!model.isEditable)
            .accessibilityLabel(RichTextControl.headings.accessibilityLabel)
            .accessibilityIdentifier(RichTextControl.headings.accessibilityLabel)
            .accessibilityValue(
                RichTextControl.activeHeadingLevel(in: model.formatState)
                    .map { RichTextControl.heading($0).accessibilityLabel } ?? ""
            )
            .accessibilityAddTraits(isActive ? [.isSelected] : [])
        }
    }
#endif
