# 50. A line dashed, and a shape filled, are the stroke's

**Status:** accepted; extends the shapes of ADR 28 and ADR 31's pen

## Context

Ink was one kind of line: whole, in the pen's colour and width. A diagram
wants more — a dashed line for what is hidden or to come, a dotted one for
a guide, a box filled with a colour — and a shape, once drawn, is ink
(strokes like any other, as OneNote keeps its shapes), so there was nowhere
else to keep how it looks. The pen itself was the page's: every page
opened began with a black pen again.

## Decision

**How a line is drawn, and what it is filled with, belong to the stroke.**
An `InkStroke` has a `line` — whole, dashed or dotted — and a `fill`, a
colour or none. Both are written only where they are not the usual, so the
format's version stays as it is (the rule of `PageDocument`: a field a
build before can ignore needs none). A build before reads such a stroke as
a whole line with no fill, and writes it so if the page is changed there:
what is lost is how the stroke looked, never the stroke.

**Dashes and dots are pieces of the line the pen took**
(`StrokeGeometry.brokenPath`), sized to its width, with round ends. The
gaps are stretched to fit a whole number: a line begins and ends with a
dash, and round an outline they are all alike, one astride where it
starts. A line dashed or dotted is as wide all along as the pen: dashes
that swelled with the hand would not read as dashes. They are worked out
once for a stroke, as its shape is.

**Of a shape, its way or outline takes the pen's line** — an arrow's head
stays whole — and graphs and solids, which have ticks and dashes of their
own, are drawn as they always were. **An outline takes the pen's fill**;
handwriting never does, or every letter with the fill left on would be
closed and coloured in. Ink already on the page is another matter: picked,
any stroke that ends where it began can be filled, a loop drawn by hand as
much as an outline.

**A fill is drawn with the pen's ink, above text and pictures**, beneath
its own line and the strokes after it. A layer of fills beneath the text
would let a label typed in a box be read whatever the fill — and would put
a shape drawn on a picture under it. So a fill has a strength instead:
light, half — as it starts — or solid. One that is not solid lets what it
is drawn round be read; a solid one covers, as correction fluid does. A
line drawn in the inverse of what is beneath it inverts its own fill there
too: the fill is laid down as it is, with the pen's layer, and the line
over everything.

**What a stroke is filled with is part of it**: a press within a filled
stroke picks it, and the eraser there removes it.

**The pen and the highlighter are the person's, not the page's**: kept in
the preferences as they are set (`pen.ink`), given to every page as it
opens, and to a page open beside the one they are changed on.

## Consequences

* Xournal++ and OneNote ink is brought in as before, whole and unfilled;
  nothing writes ink out to another format but as a picture, which is
  drawn by the same painter.
* A page with dashed or filled ink, changed on a computer running a build
  before 0.1.19, comes back with that ink whole and unfilled.
* The eraser still removes whole strokes: a dashed line is one stroke, and
  goes at a touch of any dash — or of a gap.
