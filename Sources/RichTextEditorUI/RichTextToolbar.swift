// RichTextToolbar.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

#if os(iOS)
    import SwiftUI

    // Deliberately only SwiftUI — no `RichTextCore` or `RichTextEngine` import.
    // Every decision this view appears to make is actually `RichTextControl`'s
    // pure mapping (tested on macOS) or `RichTextEditorModel`'s command/state
    // seam, so a toolbar file that compiles without seeing the engine module
    // cannot be reaching around it to poke `UITextView` directly.

    /// The declarative toolbar: one horizontally scrolling row of controls, in
    /// exactly the order the consumer declared them.
    ///
    /// A thin renderer — every decision it appears to make (which command a
    /// control sends, whether it looks active) is `RichTextControl`'s pure
    /// mapping, tested on macOS. This view only draws it and calls the model.
    struct RichTextToolbar: View {
        let controls: [RichTextControl]
        let model: RichTextEditorModel

        var body: some View {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    // Identified by position, not value: a consumer may legitimately
                    // declare the same control twice, and identical `id`s would
                    // collide in `ForEach`.
                    ForEach(Array(controls.enumerated()), id: \.offset) { _, control in
                        button(for: control)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .background(.bar)
        }

        /// Sends a control's command through the view model. This is both the
        /// buttons' action and the seam tests drive, since swift-testing cannot
        /// synthesize a SwiftUI tap.
        func tap(_ control: RichTextControl) {
            // Belt and braces: the buttons are disabled below, and the model
            // refuses commands too — but a read-only bar should not even try.
            guard model.isEditable else {
                return
            }
            // `.textColor` has no command of its own — the system picker's binding
            // issues `.setTextColor(_:)` directly as the user picks, and picking
            // black removes the color.
            guard let command = control.command else {
                return
            }
            model.apply(command)
        }

        /// The single place the view reads `model.formatState`. Both `button(for:)`
        /// and `label(for:)` route through here rather than inlining the
        /// expression, so this is also the seam the observation-dependency test
        /// drives directly.
        func isActive(_ control: RichTextControl) -> Bool {
            control.isActive(in: model.formatState)
        }

        @ViewBuilder
        private func button(for control: RichTextControl) -> some View {
            if control == .textColor {
                TextColorControl(model: model, isActive: isActive(control))
            } else {
                Button {
                    tap(control)
                } label: {
                    label(for: control)
                }
                .buttonStyle(.plain)
                .disabled(!model.isEditable)
                .accessibilityLabel(control.accessibilityLabel)
                .accessibilityIdentifier(control.accessibilityLabel)
                .accessibilityAddTraits(isActive(control) ? [.isSelected] : [])
            }
        }

        @ViewBuilder
        private func label(for control: RichTextControl) -> some View {
            let active = isActive(control)
            Group {
                if let symbol = control.systemImage {
                    Image(systemName: symbol)
                        .font(.system(size: 17, weight: .medium))
                } else if let text = control.textLabel {
                    Text(text)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                }
            }
            .toolbarControlChrome(active: active)
        }
    }

    /// The shared active/inactive chrome for a toolbar control: a 44pt square,
    /// white-on-accent when active and rounded, otherwise plain. Both
    /// `RichTextToolbar.label(for:)` and `TextColorControl`'s label apply this, so
    /// the two controls' visual states cannot drift apart.
    private struct ToolbarControlChrome: ViewModifier {
        let active: Bool

        func body(content: Content) -> some View {
            content
                // 44pt targets are preserved rather than shrunk to fit; the row
                // scrolls instead.
                .frame(width: 44, height: 44)
                .foregroundStyle(active ? Color.white : Color.primary)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(active ? Color.accentColor : Color.clear)
                )
        }
    }

    extension View {
        /// Applies the toolbar's shared active/inactive control chrome (see
        /// `ToolbarControlChrome`).
        func toolbarControlChrome(active: Bool) -> some View {
            modifier(ToolbarControlChrome(active: active))
        }
    }
#endif
