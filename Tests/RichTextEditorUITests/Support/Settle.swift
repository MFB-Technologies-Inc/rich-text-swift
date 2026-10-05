// Settle.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

import Foundation

/// Waits for a scheduled main-actor hop to land, bounded so a genuine failure
/// reports as a failed expectation rather than hanging.
///
/// This is a bounded spin (100 `Task.yield()`s) sufficient for the current
/// single main-actor hop (`RichTextEditorModel.scheduleRefresh()` schedules
/// exactly one `Task { @MainActor in ... }`), not a general condition-wait —
/// if a future change chains more hops before the state settles, this may
/// need to grow or be replaced with an actual condition check.
@MainActor
func settle() async {
    for _ in 0 ..< 100 {
        await Task.yield()
    }
}
