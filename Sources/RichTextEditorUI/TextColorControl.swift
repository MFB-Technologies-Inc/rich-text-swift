// TextColorControl.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

#if os(iOS)
    import RichTextCore
    import RichTextEngine
    import SwiftUI

    /// The `.textColor` control, backed by the system `ColorPicker`.
    ///
    /// Two consequences of using the native picker, both deliberate:
    ///
    /// - **`ColorPicker` binds a non-optional `Color`, so it cannot express
    ///   "no color".** Rather than bolt on a separate removal affordance, **black
    ///   is treated as the absence of a text color everywhere in the system**
    ///   (`RichTextColor.black`, normalized at the command and decode layers too):
    ///   picking black *is* how the user removes the color. This is more correct,
    ///   not merely simpler — an explicit `#000000` would stay black in dark mode
    ///   and become invisible against the background, whereas omitting the color
    ///   lets the theme's default adapt; for HTML output it also leaves the
    ///   choice to the consumer's own CSS.
    /// - **Its binding updates continuously while the user drags.** Every
    ///   intermediate value would otherwise become its own document mutation, so
    ///   the setter below applies only when the resolved color actually differs
    ///   from what the selection already has. (Confirmed: the realtime update
    ///   feels good and isn't sluggish — this guard is an efficiency measure, not
    ///   a workaround for a UX problem.)
    ///
    /// Colors are converted through `Color.resolve(in:)`, which yields sRGB
    /// components — the color space `RichTextColor` and the `#rrggbb` serialization
    /// already speak. An out-of-gamut pick clamps, which is what any HTML consumer
    /// would do with it anyway.
    struct TextColorControl: View {
        let model: RichTextEditorModel
        let isActive: Bool

        /// Needed to resolve a `Color` into concrete sRGB components.
        @Environment(\.self) private var environment

        /// Applies a chosen color, or removes it when `color` is nil. The tested seam.
        func select(_ color: RichTextColor?) {
            guard model.isEditable else {
                return
            }
            model.apply(.setTextColor(color))
        }

        /// What the picker shows, and what it does when changed. A mixed selection
        /// or one with no color shows black rather than inventing a value.
        ///
        /// Internal, not `private`: this type isn't `public` and isn't in a
        /// product module, so widening access here leaks nothing outside the
        /// package — it only lets `TextColorControlTests` reach the getter/setter
        /// directly (the getter's fallback, and the setter's drag guard) without
        /// needing a hosted view hierarchy.
        var selection: Binding<Color> {
            Binding(
                get: { Color(model.formatState.textColor ?? RichTextColor.black) },
                set: { newColor in
                    let resolved = RichTextColor(newColor.resolve(in: environment))
                    // The picker fires continuously while dragging; only a genuine
                    // change should reach the document.
                    guard resolved != model.formatState.textColor else {
                        return
                    }
                    select(resolved)
                }
            )
        }

        var body: some View {
            ColorPicker(
                RichTextControl.textColor.accessibilityLabel,
                selection: selection,
                supportsOpacity: false
            )
            .labelsHidden()
            .frame(width: 44, height: 44)
            .disabled(!model.isEditable)
            // Deliberately does not apply `.toolbarControlChrome(active:)` the
            // way every other control does: the well already shows the current
            // color, which is its own visual "active" state, so a second one
            // (e.g. a highlighted background) would be redundant. `isActive`
            // still drives the accessibility trait below for VoiceOver users, for
            // whom the well's color isn't itself an "active" signal.
            .accessibilityLabel(RichTextControl.textColor.accessibilityLabel)
            .accessibilityIdentifier(RichTextControl.textColor.accessibilityLabel)
            .accessibilityAddTraits(isActive ? [.isSelected] : [])
        }
    }

    extension RichTextColor {
        /// Narrows a resolved SwiftUI color to the 8-bit sRGB the model stores.
        /// Components are clamped: a wide-gamut pick can resolve outside 0...1, and
        /// `#rrggbb` has nowhere to put that.
        init(_ resolved: Color.Resolved) {
            func channel(_ value: Float) -> UInt8 {
                UInt8((min(max(value, 0), 1) * 255).rounded())
            }
            self.init(
                red: channel(resolved.red),
                green: channel(resolved.green),
                blue: channel(resolved.blue)
            )
        }
    }

    extension Color {
        /// The UI layer is the only place a framework-neutral `RichTextColor`
        /// becomes a platform color — `RichTextCore` stays Foundation-only.
        init(_ color: RichTextColor) {
            self.init(
                .sRGB,
                red: Double(color.red) / 255,
                green: Double(color.green) / 255,
                blue: Double(color.blue) / 255,
                opacity: 1
            )
        }
    }
#endif
