# 31. A lasso for the pen, and grain over the window

**Status:** accepted; adds to ADR 24's pen buttons

## Context

A pen picks things out by drawing round them, as it would on paper. The
only way to select was a marquee — a box dragged from corner to corner —
which takes in whatever lies in its rectangle: on a page written close,
the words of the line above and below along with the one wanted. The pen's
second button selected that way too.

A text box showed the band it is dragged by, and its outline, whenever the
pointer was over it, whatever tool was in hand; with a pen, writing over or
beside a box, the band came and went under the nib though nothing could
drag it.

The inverted colour, added first among the pen's colours, made thirteen:
the colours stood in two rows with one left over, alone in the middle of a
last column.

And the interface is drawn in flat colours, which some like given a little
texture.

## Decision

**A lasso tool, Lasso select (L)**, beside the select tool on the Draw tab
(`CanvasTool.lasso`). A loop drawn on the page (`Lasso`, closed from where
it ends back to where it began, inside by the even–odd rule) selects
(`CanvasController.selectWithin`):

* handwriting stroke by stroke, those with half their samples or more
  inside it, split off into an element of their own as the marquee's are —
  the two share one routine, given the box about the region and whether a
  point is in it;
* other things whole, when their middle is inside it, so a loop round a
  word written on a printout does not take the printout with it.

A tap picks what it lands on. A press on the selection's handles resizes or
turns it, and anywhere in its box moves it, so what was picked is used
without changing tools; what is selected stays selected moving between the
lasso and the select tool (`CanvasTool.selects`). Nothing is typed with
the lasso: a text box is paper to it.

**The pen's second button lassos as it starts** (`PenButtonAction.lasso`);
selecting with a box is still one of the choices. A setting already saved
is kept as it was.

**A text box shows its band and outline to the pointer only while the
select tool is in hand,** and only then shows the cursor for moving it.

**The inverted colour stands apart,** as tall as the two rows of colours
beside it, which are then twelve, six to a row. Its white and black are
split from corner to corner (`InverseHalves`) however tall it is.

**Grain, from none to strong, set in Settings → Appearance** (`Grain`). A
tile of 256 by 256 pixels of noise, made once — each pixel white or black
at random, as opaque as a bell curve has it, most faint and a few strong —
is laid over the whole window, menus and pages included, one of its pixels
to each of the screen's, as opaque as the setting. It lightens as much as
it darkens, so no colour changes on average. It is painted once, in a
layer of its own that nothing beneath it repaints, and none is laid at
all with the setting at none. Moving the slider changes the grain alone:
the themes are not built again.

## Consequences

* A loop that crosses itself leaves out what it went round twice.
* With grain, every frame puts one more picture the size of the window on
  the screen: little work for the graphics card, and none while it is off.
