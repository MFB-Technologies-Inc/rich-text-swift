// BlockStyle.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation

/// The kind of list a `listItem` block belongs to.
public enum ListKind: String, Codable, Hashable, Sendable {
    case unordered
    case ordered
}

/// The semantic role of a block (a `\n`-delimited run of the flat model).
///
/// This is the invisible source-of-truth marker (dev-plan §6a): it rides in
/// `AttributedString` storage as a custom attribute and drives encode/decode.
/// Role is NEVER inferred from visual values like font size.
public enum BlockStyle: Codable, Hashable, Sendable {
    case paragraph
    /// Heading level. v1 uses 1...3; the parser is responsible for clamping.
    case heading(Int)
    /// A list item, tagged with its list kind and nesting depth (0 = top level).
    case listItem(ListKind, depth: Int)
    /// A quoted block (`<blockquote>`).
    ///
    /// Deliberately **depth-less**, unlike `listItem`. The flat model has no
    /// way to express "a quote inside a quote" as anything but a role on a
    /// single block, and there is no v1 command that could create or unwind a
    /// nesting level, so a depth parameter would be a number nothing ever
    /// sets and nothing ever renders. Nested `<blockquote>` markup therefore
    /// flattens to one quoted block on import (see `HTMLDecoder`), and a
    /// list inside a quote decodes as a plain list — list membership is the
    /// more specific role and the flat model cannot hold both.
    ///
    /// v1 imports, renders and exports blockquote but offers no toolbar
    /// control for it — the v1 control set does not include one. This is
    /// import/export/render fidelity, not an authoring feature.
    case blockquote
}

extension BlockStyle {
    /// The role of an empty block from the blocks on either side of it (GitHub
    /// issue #74). An empty block has no characters to carry a role (D13), so
    /// one between two items of the same list (same kind and depth) is an empty
    /// item of that list, not a paragraph that splits it. Any other empty block
    /// has no role of its own. The encoder and `BlockScanner` both use this, so
    /// what the editor shows and what it saves agree.
    package static func roleOfEmptyBlock(between previous: BlockStyle?, and next: BlockStyle?) -> BlockStyle? {
        guard case .listItem = previous, previous == next else { return nil }
        return previous
    }
}
