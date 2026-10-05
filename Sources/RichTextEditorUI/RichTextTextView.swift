// RichTextTextView.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

#if os(iOS)
    import RichTextCore
    import RichTextEngine
    import UIKit
    import UniformTypeIdentifiers

    /// The `UITextView` the representable builds, which owns what a paste puts
    /// into the document.
    ///
    /// UIKit's own rich paste keeps the pasteboard's fonts and colors in
    /// `textStorage` while the semantic read-back drops them, so what the user
    /// sees is not what gets saved. By default this type decodes
    /// the pasteboard's HTML into the semantic model instead and inserts it
    /// through the engine, which keeps bold, headings and lists and draws them
    /// in the theme. Consumers who want no formatting at all can opt into plain
    /// text via `RichTextEditor(text:pasteAsPlainText:)`.
    final class RichTextTextView: UITextView {
        /// What a `paste(_:)` should actually do. Factored out of the override so
        /// the *rule* is a pure function that tests can pin exhaustively —
        /// including the two cases that must not insert anything, which are
        /// otherwise only observable as an absence.
        enum PasteDisposition: Equatable {
            /// Let `UITextView` paste as it always has. Only for a pasteboard
            /// with no text at all.
            case system
            /// Insert exactly this plain text.
            case insert(String)
            /// Insert this semantic fragment through the engine.
            case insertRich(AttributedString)
            /// Insert nothing at all.
            case nothing
        }

        /// Set from `RichTextEditorRepresentable`, which mirrors the value the
        /// consumer passed to `RichTextEditor.init`.
        var pasteAsPlainText = false

        /// Where pasted plain text comes from.
        ///
        /// Injectable out of necessity, not taste: `UIPasteboard.general` is
        /// unusable from this package's simulator test bundle. With no host
        /// application, the first access blocks the main thread and never
        /// returns — measured here, and it hangs *every* test in the bundle, not
        /// just the one that touched it. Overriding this closure is the only way
        /// the paste path can be driven under test at all. Production reads the
        /// system pasteboard, and only when the disposition below actually needs
        /// the string.
        var plainTextForPaste: () -> String? = { UIPasteboard.general.string }

        /// Where pasted HTML comes from. Injectable for the same reason as
        /// `plainTextForPaste`, so this default is the one line of the rich
        /// paste no test runs (GitHub issue #40).
        var htmlForPaste: () -> String? = { RichTextTextView.pasteboardHTML(UIPasteboard.general) }

        /// Set from `RichTextEditorRepresentable`. Weak because the engine
        /// already holds this view.
        weak var engine: UIKitEditorEngine?

        override func paste(_ sender: Any?) {
            switch Self.disposition(
                pasteAsPlainText: pasteAsPlainText,
                isEditable: isEditable,
                html: htmlForPaste,
                plainText: plainTextForPaste
            ) {
            case .system:
                super.paste(sender)
            case let .insert(string):
                // Route through the normal text-input path rather than mutating
                // storage: `insertText(_:)` stamps the view's `typingAttributes`
                // onto the inserted characters, and the engine keeps those loaded
                // with the caret block's semantic `blockStyle` marker plus the
                // user's own inline state
                // (`UIKitEditorEngine.pushTypingAttributes()`). So the paste
                // lands exactly as if the user had typed it, and the existing
                // delegate wiring (`textViewDidChange` ->
                // `RichTextEditorModel.synchronizeFromTextView()`) pulls the
                // result back out through the model seam — nothing writes to the
                // document behind the model's back.
                insertText(string)
            case let .insertRich(fragment):
                guard let engine else {
                    super.paste(sender)
                    return
                }
                // The engine renders, records undo and reports the edit through
                // `textViewDidChange`, so the binding hears about it the same way
                // it hears about typing.
                engine.insert(fragment)
                // UIKit's own paste names its step; without this the undo
                // alert reads a bare "Undo".
                undoManager?.setActionName("Paste")
                scrollRangeToVisible(selectedRange)
            case .nothing:
                break
            }
        }

        /// The paste rule.
        ///
        /// - A read-only editor takes no paste, whatever route it arrives by —
        ///   the same rule `RichTextEditorModel` applies to commands. UIKit
        ///   already hides the menu item, but `paste(_:)` stays reachable (⌘V, a
        ///   `UIKeyCommand`, another responder forwarding).
        /// - By default, HTML that decodes to some text is `.insertRich`. Failing
        ///   that, plain text is `.insert`, typed in with the caret's own
        ///   attributes; RTF-only sources land here. A pasteboard with no text at
        ///   all is `.system`, UIKit's paste as it always was.
        /// - With `pasteAsPlainText`, the HTML is never read, and a pasteboard
        ///   with no text at all — an image, say — inserts
        ///   **nothing**, and deliberately does *not* fall back to `.system`.
        ///   Falling back would insert an `NSTextAttachment` carrying the
        ///   pasteboard's own attributes: exactly the see-one-thing/save-another
        ///   divergence this option exists to prevent, and as content the
        ///   semantic model cannot represent at all, so it would vanish on the
        ///   next read-back. Inserting nothing is the honest outcome — the
        ///   option's contract is that only plain text ever enters the document.
        ///
        /// `html` and `plainText` are closures rather than values so each is
        /// read only on the branch that needs it.
        static func disposition(
            pasteAsPlainText: Bool,
            isEditable: Bool,
            html: () -> String?,
            plainText: () -> String?
        ) -> PasteDisposition {
            guard isEditable else { return .nothing }
            if !pasteAsPlainText, let html = html() {
                let fragment = RichTextHTML.decode(html)
                if !fragment.characters.isEmpty {
                    return .insertRich(fragment)
                }
            }
            guard let string = plainText(), !string.isEmpty else {
                return pasteAsPlainText ? .nothing : .system
            }
            return .insert(normalizingLineEndings(string))
        }

        /// The pasteboard's HTML, if it has any. Safari hands it over as a
        /// string; Word and Outlook as data, in UTF-8 or, from older Windows
        /// builds, Windows-1252.
        static func pasteboardHTML(_ pasteboard: UIPasteboard) -> String? {
            let type = UTType.html.identifier
            guard pasteboard.contains(pasteboardTypes: [type]) else { return nil }
            if let string = pasteboard.value(forPasteboardType: type) as? String {
                return string
            }
            guard let data = pasteboard.data(forPasteboardType: type) else { return nil }
            return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252)
        }

        /// Converts CRLF, lone CR, U+2029 and U+0085 to LF.
        ///
        /// `\n` is the only block separator the model knows (`BlockScanner`), and
        /// a Windows-authored paste — which is what Word and Outlook actually put
        /// on the pasteboard — otherwise leaves a stray `\r` *inside* a block,
        /// where it survives every round trip (GitHub issue #12). Normalizing on
        /// ingest is the fix that issue asks for, applied to the one ingest path
        /// this type owns.
        ///
        /// The rule itself is `LineEndings.normalized(_:)`, shared with the
        /// engine's own ingest path.
        static func normalizingLineEndings(_ string: String) -> String {
            LineEndings.normalized(string)
        }
    }
#endif
