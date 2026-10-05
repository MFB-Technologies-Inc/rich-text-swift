# Manual testing

## Setup

1. Build and run the demo app (see "Demo app" in the README) on an iPad simulator. Use an iPad:
   the Editor, HTML and Load tabs sit at the top of the screen there, while on iPhone the keyboard
   covers them and the demo has no way to dismiss it.
2. Keep Device Hub open. It copies the Mac clipboard to the simulator.
3. Load a paste sample onto the clipboard from the repo root:

   ```bash
   swift Demo/Scripts/pasteboard.swift Demo/PasteFixtures/headings.html
   ```

   The script writes the file as `public.html` plus a plain-text version, which is what a browser
   or Word puts there. Give Device Hub a few seconds, then check that it arrived with
   `xcrun simctl pbpaste <udid>` (it prints the plain-text version). Don't copy anything on the
   Mac between loading a sample and pasting it; Device Hub will replace the sample.
4. Paste by tapping the caret and choosing Paste from the menu, or with the paste button at the
   left of the keyboard's shortcut bar.
5. The saved document is the "Encoded HTML" text on the HTML tab. Every expected HTML result below
   is that text, exactly.

Start each test by tapping Clear, unless the test says otherwise.

## Paste

**P1. Headings on an empty line.** Load `headings.html` and paste.
The editor shows an H1, an H2 and a paragraph with bold and italic, all in the theme's fonts. The
HTML tab shows:

```html
<h1>Pasted heading one</h1>
<h2>Pasted heading two</h2>
<p>Body with <b>bold</b> and <i>italic</i>.</p>
```

**P2. The source's styling is dropped.** Load `foreign-styling.html` and paste. The sample asks for
a red 28px heading and a blue Georgia paragraph. The editor shows a theme H2 and a body-font
paragraph, neither red nor blue:

```html
<h2>Styled heading</h2>
<p>Georgia paragraph with <b>bold</b> and <i>italic</i></p>
```

**P3. The first block joins the line it lands on.** Load the Everything sample from the Load tab,
put the caret at the end of "The end.", load `headings.html` and paste. "Pasted heading one"
joins "The end." as paragraph text and loses its H1. "Pasted heading two" is still an H2. This is
the rule in `EngineCore.insert`: a paste never changes the role of text you didn't select.

**P4. A Word document.** Load `word.html` and paste. It carries Word's `<head>`, `<style>`,
`<o:p>` tags and `mso-` styles. Only this survives:

```html
<h1><span style="color:#2f5496">Word heading</span></h1>
<p>Word body with <b>bold</b> and <i>italic</i>.</p>
<p> </p>
<p>Second Word paragraph.</p>
```

Word's 20pt size and Calibri are gone. Its heading color stays, because a color on a `<span>` is a
text color the document keeps. The `<p> </p>` is Word's `&nbsp;` spacer paragraph.

**P5. Windows-1252 bytes.** Load the sample with the flag, then paste:

```bash
swift Demo/Scripts/pasteboard.swift --cp1252 Demo/PasteFixtures/windows-1252.html
```

Expected: `<p>Café costs 5€ – “quoted”</p>`, with no mangled characters. Passing this doesn't
prove `RichTextTextView.pasteboardHTML(_:)` took its Windows-1252 branch. Device Hub may hand
the simulator a string instead of the raw bytes, and both paths give this result.

**P6. Lists.** Load `list.html` and paste:

```html
<ul><li>pasted bullet one</li><li>pasted <b>bullet</b> two</li></ul><ol><li>pasted step one</li><li>pasted step two</li></ol>
```

**P7. Plain text takes the caret's formatting.** Load the Everything sample, then load plain text
only:

```bash
swift Demo/Scripts/pasteboard.swift --text "PLAIN"
```

Put the caret between "Small" and "heading" and paste. "PLAIN" lands inside the H3 at H3 size,
and the H3 stays an H3.

**P8. One undo step.** Do P1, then shake (`idb ui shake --udid <udid>`). The alert reads "Undo
Paste". Tap Undo: the whole paste disappears in one step and the document is empty again. Redo
brings all of it back.

**P9. Paste as plain text.** Turn on Options > Paste as plain text, load `headings.html` and
paste. The text arrives as three plain paragraphs with no bold or italic.

**P10. Read-only.** Turn off Options > Editable, load `headings.html`, and long-press the text.
The menu has no Paste, and nothing you do changes the document.

**P11. Real sources.** Copy from each of these and paste. Say in the PR which ones you tried.

- Safari in the simulator: select a heading and a paragraph on any page. Expect P1's result.
- Word or Outlook, on a device: expect P4's result.
- Notes, on a device: expect plain text, as in P7. Notes is believed to offer only RTF, which
  the editor pastes as plain text. Nobody has confirmed that yet.

## Undo

These cover engine undo: formatting commands and Return register
their own undo steps on the text view's undo manager, between the steps UIKit records for typing.
`EngineUndoTests` groups undo by hand, and GitHub issue #27 explains why that isn't enough: two
versions of the caret-Bold fix passed every test and still misbehaved in the app. Type with the
on-screen keyboard, not by pasting.

Undo and redo with the arrows at the left of the iPad keyboard's shortcut bar, or by shaking.
The arrows grey out when there is nothing left to undo or redo. Watch the toolbar as well as the
text: a highlighted button is a format that the next typed character will get.

**U1. Type, Bold, type, then undo.** Clear, type "one", tap Bold, type "two". "two" is bold. Undo
three times:

1. The first undo removes "two" and leaves Bold highlighted.
2. The second turns Bold off and changes no text.
3. The third removes "one", and the undo arrow greys out.

**U2. Redo the same sequence.** Continue from U1. Redo three times:

1. "one" comes back plain, with Bold off.
2. Bold turns on and no text changes.
3. "two" comes back bold, and the redo arrow greys out.

**U3. Bold a selection.** Clear, type "hello", double-tap it to select it, and tap Bold. The HTML
tab shows `<p><b>hello</b></p>`. Back on the editor, undo: `<p>hello</p>`. Redo:
`<p><b>hello</b></p>` again.

**U4. Undo reaches the saved document.** The HTML tab is the binding's copy of the document, so
U3's checks are also this one: after an engine undo or redo, the HTML tab matches what the editor
shows without any further edit.

**U5. Return in a list.** Clear, tap the bullet-list button, type "one", press Return, type
"two". Undo four times:

1. "two" goes, and the empty second item keeps its bullet, with the list button highlighted.
2. The Return goes: one item, "one", caret at its end.
3. "one" goes. The document is empty and the list button is still highlighted.
4. The list button turns off, and the undo arrow greys out.

**U6. Loading a document clears undo.** Type anything, then load the Everything sample from the
Load tab. Back on the editor, the undo and redo arrows are both grey. The loaded document replaced
the old one wholesale and recorded no undo step, so the old steps can't be replayed against it.

## Lists

These cover list items that sit more than one level deeper than the item before them. HTML only allows `<li>`
as a child of `<ul>` and `<ol>`, so the encoder opens an empty `<li>` for each skipped level to
hold the next list, and the decoder folds that placeholder back into the item below it. The
placeholder is `<li style="display:block">`, so a browser neither draws a marker for it nor
counts it. The
toolbar has no indent button, so a skipped level arrives through loaded or pasted HTML, or by
deleting the item between two levels (L7).

Load each input from the Load tab: paste it into Custom HTML and tap "Load into editor". Both
Round trip rows on the HTML tab should be green in every test here.

Every input starts with a ruler: a "Ruler" paragraph, one bullet at each of the first three
depths, and a "Test" paragraph. The editor draws the ruler with the theme's real indents, so
"at step 2" below means the item's text starts where "step 2" starts. List indent depends only
on depth, never on the list's kind, so a numbered item lines up with the bullets too. A bullet
at step N also gets the same marker as the ruler's "step N" line, so compare markers against the
ruler rather than by name: at the default text size the depth-1 marker, `◦`, is hard to tell from
the depth-0 `•`. The paragraphs end the ruler's list, so the ruler doesn't change how the test
list is numbered or encoded, and every expected HTML result starts with the same three ruler
lines.

**L1. An old document is fixed on the next save.** Load the shape the encoder wrote before #49:

```html
<p>Ruler</p>
<ul><li>step 1<ul><li>step 2<ul><li>step 3</li></ul></li></ul></li></ul>
<p>Test</p>
<ol><li>a<ol><ol><li>b</li></ol></ol></li></ol>
```

The editor shows "1. a" at step 1 and "1. b" at step 3, with nothing at step 2. The HTML tab
shows:

```html
<p>Ruler</p>
<ul><li>step 1<ul><li>step 2<ul><li>step 3</li></ul></li></ul></li></ul>
<p>Test</p>
<ol><li>a<ol><li style="display:block"><ol><li>b</li></ol></li></ol></li></ol>
```

**L2. The first item is two levels deep.** Load:

```html
<p>Ruler</p>
<ul><li>step 1<ul><li>step 2<ul><li>step 3</li></ul></li></ul></li></ul>
<p>Test</p>
<ol><ol><ol><li>text0</li></ol></ol></ol>
```

The editor shows "1. text0" at step 3, directly under "Test", with no blank lines between them.
The HTML tab shows:

```html
<p>Ruler</p>
<ul><li>step 1<ul><li>step 2<ul><li>step 3</li></ul></li></ul></li></ul>
<p>Test</p>
<ol><li style="display:block"><ol><li style="display:block"><ol><li>text0</li></ol></li></ol></li></ol>
```

**L3. Mixed kinds, then back to the skipped level.** Load:

```html
<p>Ruler</p>
<ul><li>step 1<ul><li>step 2<ul><li>step 3</li></ul></li></ul></li></ul>
<p>Test</p>
<ul><li>a<ol><li style="display:block"><ol><li>b</li></ol></li></ol><ul><li>c</li></ul></li></ul>
```

The editor shows "a" at step 1, "1. b" at step 3 and "c" at step 2, each bullet matching the
ruler's marker at its step. The HTML tab shows the input unchanged. The skipped level takes the
kind of the item that skipped it, so "c" closes that `<ol>` and opens its own `<ul>`.

**L4. A placeholder item adds no line.** Load:

```html
<p>Ruler</p>
<ul><li>step 1<ul><li>step 2<ul><li>step 3</li></ul></li></ul></li></ul>
<p>Test</p>
<ul><li><ul><li>b</li></ul></li></ul>
```

The editor shows one line under "Test": "b" at step 2 with step 2's marker, and no empty bullet
above it. Before #49, "b" loaded at step 1. This input uses a plain `<li>` as the placeholder,
the way other editors write it, and the HTML tab shows the encoder's own placeholder instead:

```html
<p>Ruler</p>
<ul><li>step 1<ul><li>step 2<ul><li>step 3</li></ul></li></ul></li></ul>
<p>Test</p>
<ul><li style="display:block"><ul><li>b</li></ul></li></ul>
```

**L5. Return at the deep level.** Load L1's input, put the caret at the end of "b", press Return
and type "c". The editor shows "1. b" and "2. c", both at step 3. The HTML tab shows:

```html
<p>Ruler</p>
<ul><li>step 1<ul><li>step 2<ul><li>step 3</li></ul></li></ul></li></ul>
<p>Test</p>
<ol><li>a<ol><li style="display:block"><ol><li>b</li><li>c</li></ol></li></ol></li></ol>
```

**L6. Changing the kind at the deep level.** Load L1's input, put the caret in "b" and tap the
bullet-list button. "b" loses its number and takes step 3's square marker, still at step 3. The
HTML tab shows:

```html
<p>Ruler</p>
<ul><li>step 1<ul><li>step 2<ul><li>step 3</li></ul></li></ul></li></ul>
<p>Test</p>
<ol><li>a<ul><li style="display:block"><ul><li>b</li></ul></li></ul></li></ol>
```

**L7. Deleting the middle level.** Load:

```html
<p>Ruler</p>
<ul><li>step 1<ul><li>step 2<ul><li>step 3</li></ul></li></ul></li></ul>
<p>Test</p>
<ul><li>a<ul><li>b<ul><li>c</li></ul></li></ul></li></ul>
```

The editor shows one item at each step, matching the ruler. Tap just before "b", press
Shift-Down on the Mac keyboard to extend the selection to the start of "c", and press Delete.
Before you delete, the highlight runs from "b" to the right edge of its line, the end handle
sits at that edge, and "c" isn't highlighted: that's the line break after "b" selected, which
is what this test needs. The selection must stop before "c". Dragging the handle usually lands
just after it, which deletes "c" too and leaves an empty paragraph instead.

"b" is gone and "c" keeps its own depth, so the editor shows "a" at step 1 and "c" at step 3 with
step 3's marker, and nothing at step 2. This is the one way to make a skipped level without
loading HTML. The HTML tab shows:

```html
<p>Ruler</p>
<ul><li>step 1<ul><li>step 2<ul><li>step 3</li></ul></li></ul></li></ul>
<p>Test</p>
<ul><li>a<ul><li style="display:block"><ul><li>c</li></ul></li></ul></li></ul>
```

**L8. In a browser.** Do L3. Copy this command into Terminal on the Mac, but don't run it yet:

```bash
xcrun simctl pbpaste booted > /tmp/l8.html && open -a Safari /tmp/l8.html
```

Now tap Copy on the HTML tab, then go back to Terminal and press Return. The order matters.
Device Hub copies the Mac clipboard into the simulator, so copying the command after tapping
Copy replaces the HTML with the command, and Safari shows the command as the page's text.

Safari shows the same levels and markers as the editor, ruler included: "a" at step 1, "1. b"
at step 3, "c" at step 2, and nothing at step 2 between "a" and "b". The placeholder `<li>` is
`display:block`, so Safari draws no marker for it and doesn't count it. Before the placeholder
had that style, Safari showed a bare "1." at step 2 and numbered a later step-2 item one higher
than the editor did.

To check the markup itself, wrap the fragment in a minimal document:

```html
<!DOCTYPE html>
<html lang="en">
<head>
<title>Test</title>
</head>
<body>
<!-- the Encoded HTML goes here -->
</body>
</html>
```

Paste that into the [W3C validator](https://validator.w3.org/nu/#textarea). It reports no errors
and no warnings.
