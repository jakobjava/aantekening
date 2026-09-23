# 14. Right-click menus, one clipboard, and backgrounds

**Status:** accepted

## Context

Everything on a page could be made and moved, but not copied: a text box's
own Ctrl+C carried rich text between boxes, and a picture in a box, which has
no text, copied as nothing at all. Things on the page itself — pictures, PDF
pages, drawings, whole boxes — had no copy and paste of any kind. Nor was
there a right-click menu, apart from the corrections for a word spelled
wrongly. And a PDF printout or a picture to annotate kept being picked up by
clicks meant for the writing over it; OneNote's answer is to set it as the
page's background.

## Decision

* **One clipboard** (`NoteClipboard`) for what can be copied: text from a
  box with its formatting, formulas and pictures (`TextClip`), whole things
  on the page (`ElementsClip`), or text from elsewhere (`PlainClip`). The
  system clipboard is given the plain text, which is what other applications
  receive; what was copied here is pasted from here while the system
  clipboard still holds that text. Pasted things are copies with identifiers
  of their own (`NoteElement.copiesOf`), a step on from what they copy, or at
  the right-click or bare caret where they were pasted. Things from the page
  pasted into a box's text go in as text and as objects where they can
  (`ElementsClip.asBlocks`), and onto the page where they cannot; at a bare
  caret on the paper, with no text yet to go into, they land on the page as
  themselves. Text pasted onto the page comes in a new box. Paste Text Only, and Ctrl+Shift+V, paste the plain text.
* **Right-click menus**, as OneNote's: the Home tab's text formatting across
  the top (`MiniToolbar`, the ribbon's own buttons, so they act as they do
  there), then Cut, Copy, Paste and Paste Text Only, setting a picture as the
  background, and Delete. What was right-clicked is picked first, so the menu
  acts on it. The canvas reports a right-click (`onContextMenu`) except where
  an element's own widget takes the press; a text box then opens its menu,
  with the spelling corrections first, and the page lends it the toolbar
  (`CommandMenuHeader`).
* **Backgrounds are locked elements.** Every element already carried a
  `locked` flag that selection passed over; "Set Picture As Background"
  sets it, and moves the element to the back. The canvas draws locked
  elements in a layer of their own beneath all ink, and takes no presses on
  them; a right-click on one offers to take it out of the background again,
  ticked. A picture or PDF page inside a text box is taken out of the box to
  lie where it was drawn — one undo step, and a box left empty goes with it.
  Embeds and elements convert through one pair of functions in core
  (`NoteElement.asEmbed`, `EmbedOnPage.toElement`), which the importer uses
  too.

## Consequences

* Copying works the same for everything on a page, and between pages of a
  workspace, which share their assets.
* A copy with no text of its own — a picture — leaves the system clipboard
  empty, so it pastes until text is copied elsewhere. Pictures copied in
  other applications cannot be pasted yet: Flutter's clipboard carries only
  text.
* On a touch screen the menu is not yet opened by a long press.
