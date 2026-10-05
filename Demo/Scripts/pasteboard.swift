// pasteboard.swift
// SwiftRichText
//
// This source code is licensed under the MIT License (MIT) found in the
// LICENSE file in the root directory of this source tree.

// Puts an HTML file on the Mac clipboard the way a browser or Word does:
// `public.html` plus a plain-text version. Device Hub copies the clipboard
// to a running simulator, so the demo app can then paste it.
//
//     swift Demo/Scripts/pasteboard.swift Demo/PasteFixtures/headings.html
//     swift Demo/Scripts/pasteboard.swift --cp1252 Demo/PasteFixtures/windows-1252.html
//     swift Demo/Scripts/pasteboard.swift --text "plain words only"
//
// `--cp1252` stores the HTML as Windows-1252 bytes instead of a UTF-8 string,
// the shape older Windows builds of Word hand over.

import AppKit

var arguments = Array(CommandLine.arguments.dropFirst())
let pasteboard = NSPasteboard.general

if arguments.first == "--text", arguments.count == 2 {
    pasteboard.clearContents()
    pasteboard.setString(arguments[1], forType: .string)
    print("Clipboard: plain text only")
    exit(0)
}

let cp1252 = arguments.first == "--cp1252"
if cp1252 {
    arguments.removeFirst()
}

guard arguments.count == 1, let html = try? String(contentsOfFile: arguments[0], encoding: .utf8) else {
    FileHandle.standardError.write(Data("usage: pasteboard.swift [--cp1252] <file.html> | --text <string>\n".utf8))
    exit(64)
}

let plain = (try? NSAttributedString(
    data: Data(html.utf8),
    options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue],
    documentAttributes: nil
))?.string ?? html

pasteboard.clearContents()
if cp1252 {
    guard let data = html.data(using: .windowsCP1252) else {
        FileHandle.standardError.write(Data("\(arguments[0]) has characters Windows-1252 can't hold\n".utf8))
        exit(65)
    }
    pasteboard.setData(data, forType: .html)
} else {
    pasteboard.setString(html, forType: .html)
}

pasteboard.setString(plain, forType: .string)
print("Clipboard: \(arguments[0]) as HTML\(cp1252 ? " (Windows-1252 bytes)" : ""), plus plain text")
