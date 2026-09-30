# 21. The page follows the view as one transform

**Status:** accepted; supersedes the last consequence of ADR 5; how the page follows a zoom revised by ADR 27

## Context

A notebook imported from OneNote — thirty pages of printouts with
handwriting over them — scrolled at a dozen frames a second on a fast
desktop, and would drain a laptop's battery. Measured in a profile build,
scrolling a page of 300 ink elements and 40,000 samples took 80 ms to draw
each frame, and every frame of scrolling also:

* drew each pen stroke as one line per pair of samples, since a single path
  has a single width: tens of thousands of draws, which Impeller, keeping
  nothing between frames, tessellated again every frame;
* rebuilt and laid out every element widget at its new place on screen, and
  repainted the whole window around them, ribbon and sidebar included;
* rebuilt the page's map and drew every stroke of the page again, small.

## Decision

**A stroke whose width follows pressure is one filled outline.** Each side
is offset by half the width at every sample, with round ends; a sharp turn
ends one run and starts the next, so the sides never cross, and every run is
wound the same way, so their overlaps are their union
(`StrokeGeometry.pressurePath`).

**The page's layers are laid out in page units, and the view is one
transform.** `PageSpace` lays its layers out over a region of the page and
shows them through a transform set on the layer they are composited in;
scrolling and zooming change that transform alone. The region is the view
and a quarter to a half of it again on every side, on a grid, so the layers
are built again only when the view has moved out of it or zoomed.
`PagePlacement` places each element at its frame, turned about its middle.

Hit-testing and keyboard focus survive where ADR 5 feared they would not:
both render objects hit their children through the transform without
asking whether the point is inside their own box, and report the transform
to `applyPaintTransform`, so a text box knows where it is on screen for its
caret, its menus and the input method.

**The controller says what changed.** `CanvasController.view` is the view
alone, `contents` everything else, `wetInk` the stroke in progress. The
canvas rebuilds for contents; the paper, the selection, the scrollbars and
the map repaint for the view; the stroke in progress repaints for its
samples.

**The map keeps its ink as pixels**, drawn once each time a layer of it is
painted: small, it holds hundreds of strokes in few pixels, and each costs
as much to draw however small.

## Consequences

* The same page scrolls at under 4 ms a frame, of which under 1 ms on the
  UI thread; scrolling it for five seconds costs a tenth of the CPU time.
* Pressure-varying ink is drawn at the width its samples give it. Drawn as
  overlapping segments, the edges of each darkened the next, and it looked
  a little bolder than that.
* A new ink sample, a caret blinking, or the view moving repaints one layer
  each. What is outside the region is not built, so a long page costs what
  is near the view.
* Anything placed on the page must be placed through `PagePlacement`: a
  widget positioned on screen by itself would not follow the view.
