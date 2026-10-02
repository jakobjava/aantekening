# 24. Icons beside the words, and the pen as it is held

**Status:** accepted; revises ADR 18's words-only buttons, and adds to ADR
23; the pen's second button lassos as it starts, by ADR 31

## Context

ADR 18 dropped icons for words. A ribbon, a sidebar and menus of words
alone read slowly: the eye finds a button by its shape before it reads it.
Borrowed icon sets do not fit an interface of thin straight lines, and Google's
Material icons are what the person using it wants least.

A pen is not a mouse. Its hand trembles, most of all held still — so holding
it still to make a shape did not always work, and the trembling where it
rested could be read as an arrowhead drawn at the end of a line. Its two
buttons did the wrong things: Linux reports the second as the button a mouse
has in its middle, so it scrolled the page, and the first did nothing.

## Decision

**Icons, drawn, beside the words.** `AppIcon` is a set of icons each a few
thin lines on a grid of sixteen, drawn by the app as its marks are (ADR 18),
in the colour of the text beside them and greyed out with it. They never
replace a word: a tall ribbon button shows its icon over its name, a small
one before it; the sidebar's buttons have theirs above the name written up
the strip; the settings' pages, the bin and the commands of menus theirs
before their names. What is better shown some other way — formatting as the
letter it formats, a colour, a formula, the zoom — keeps that.

**The pen, set as it is held** (Settings → Pen, kept for this machine):

* *Smoothing*: the line trails the pen by a few screen pixels, as if pulled
  on a string (`CanvasController.inkSmoothing`), so a tremor shorter than the
  string moves nothing; it catches up where the pen lifts, or holds still to
  make a shape. Off unless chosen.
* *Buttons* (`PenButtons`): what the pen does touching the page with its
  first or second button held — erase, select, scroll or nothing; erase and
  select unless changed — whatever tool is in hand. The settings page shows
  which button is which as it is pressed over it. The other end of a pen
  always erases. Drawing again lets go of what was selected.
* *Shapes on holding still* can be turned off.

**The nib for a cursor.** Over the page the pen shows a dot as thick as its
line and in its colour, the highlighter its chisel and the eraser its reach
(`NibPainter`), each ringed in white and grey so it shows on paper and on a
dark picture, in place of the crosshair, which showed none of that.

**Held still means still enough for what holds it**: a mouse within 4
pixels, a pen within 10 and a finger within 12, for half a second; and the
trembling where it rested is left out of what the stroke is read as.

## Consequences

* A new command on the ribbon or in a menu can be given an icon from
  `AppIcon`, or a new one drawn in the same lines; none comes from a font.
* Buttons with icons take a little more room: the ribbon scrolls sideways
  sooner in a narrow window.
