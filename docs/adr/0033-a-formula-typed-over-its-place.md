# 33. A formula typed over its place, and a caret that lets presses through

**Status:** accepted; revises how ADR 10 shows the formula being edited, and
how ADR 26's caret takes presses

## Context

The formula being edited was laid out in its line as its source (ADR 10). A
source is far wider than the formula it typesets: it wrapped, the box grew,
and whatever lay beneath the box moved down as it was typed. The preview
beneath stood 6 units left of the source and 24 wider, so it hung out
further on the right than on the left, and widened with every key.

A caret placed on the paper is an empty box as wide as the narrowest box
(ADR 26). Placed just beside a box, it lay over that box's edge and took
the clicks meant for it, until a click far away moved the caret off.

A right-click on a text box was the box's own: it put the caret in the box,
and so picked that box alone, even out of everything Ctrl+A had picked.

A formula begun at a caret left the caret looking like a caret, a tinted
box floating on the paper with no box round it. And the caret beside a
picture or PDF page in a box was as tall as the object.

## Decision

**The text keeps the formula's place; its source is drawn over it.** The
formula being edited stands in the laid-out text as one character, as every
formula does (`BlockView`), at the size it was typeset when it was opened,
drawn blank; a new one has a small room to type into. Its source is typed
in a field as wide as the box, padding included, its first line on the
formula's and as many beneath as it needs. The box lays the field out
(`FormulaLayer`); the canvas draws it over everything on the page, the
frame and handles round the box included (`InfiniteCanvas.overlay`), where
the box is (a `CompositedTransformFollower`), so it zooms, pans and turns
with it. A press on the field is the box's, wherever the field reaches. A
box sizing itself to its text is at least `TextBoxEditor.formulaWidth` wide
while a formula is typed in it, so the field has room. The caret, the
selection, highlights and text being composed are drawn in the field.

Nothing changes in how it is typed. The arrow keys move through the source
and out at either end into the text; Shift carries a selection out of it.
While a formula is open the input method sees its source alone.

**The preview's left edge is under the source's,** and it is as wide as the
source where that is wider than its least width, so it widens only with a
source wider than it.

**A caret placed takes no presses** (`TextBoxEditor.caretOnly`, and
`CanvasController.passesOver`): a click, or a selection dragged across the
page, goes through it to what lies beneath. A click on the box it lies over
types in that box; a click on bare paper places the caret anew.

**A formula begun at a caret shows as the box it will be**: its band and
an outline of its own, and it takes presses, so its source can be clicked
in. It is still nothing written — kept out of history, and gone when left
empty — so the page's frame and handles come with the first thing typed in
it, as they do with words.

**A right-click on several things picked together is the page's, for all of
them** (`CanvasController.pressesGroup`), as a press there moves all of
them: on any of them, text boxes included, or on the paper between them.
They stay picked, and the menu's toolbar formats every box among them.

**The caret beside a picture or PDF page is a line of text tall,** standing
on the object's lower edge, as on the line it would be typed on.

## Consequences

* Nothing moves as a formula is typed. Once it is finished it is typeset at
  its new size, and the text after it moves then, once.
* The field covers the formula's own line, and the lines beneath it, while
  it is typed; the words beside the formula show again once it is
  finished.
* A narrow box sizing itself to its text widens while a formula is typed in
  it, and narrows again after.
* Tests of what the input method sees in a formula see its source alone.
