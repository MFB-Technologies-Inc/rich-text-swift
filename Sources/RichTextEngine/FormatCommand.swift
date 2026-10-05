// FormatCommand.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation
import RichTextCore

/// A formatting intent — the "command" half of the internal command/state seam
/// (dev-plan Decision #6). Covers exactly the v1 toolbar.
///
/// Kept module-internal in v1 (the module is not a package product); promoting
/// it to a shipped public API is the additive "bring your own toolbar" work.
public enum FormatCommand: Hashable, Sendable {
    case toggleBold
    case toggleItalic
    case toggleUnderline
    case toggleStrikethrough
    /// `nil` removes the color attribute (back to theme default).
    case setTextColor(RichTextColor?)
    /// The primitive: set every intersecting block to exactly this style.
    case setBlockStyle(BlockStyle)
    /// Toolbar H1–H3: sets the heading, or reverts to `.paragraph` if every
    /// intersecting block is already that heading level.
    case toggleHeading(Int)
    /// Toolbar UL/OL: makes list items, or reverts to `.paragraph` if every
    /// intersecting block is already a list of that kind. Existing nesting
    /// depth is preserved (M3 decision D12).
    case toggleList(ListKind)
}
