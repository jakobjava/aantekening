# 42. Text kept built out of view, and zoomed as a picture

**Status:** accepted; revises which of ADR 27's elements are let go as the
view moves on, and how its page is drawn while it zooms

## Context

Scrolling and zooming still lagged on two pages of notes: one of three
printouts with twenty-four formulas in six text boxes over them, and one of
three pictures and five boxes of German text. Measured with the benchmark
(`app/aantekening/benchmark`) on those pages, with the person's own
settings and dictionaries, in a profile build at 2× under KDE on Wayland:

* **A box of formulas coming into view stopped the scroll.** The page
  builds only what lies about the view (ADR 27) and lets go of the rest; a
  box scrolled back to was built and laid out anew, and a formula is a tree
  of a widget for every symbol. Frames of a scroll took up to 37 ms to
  build, nearly all of it laying out formulas, and as long again once a
  pinch had zoomed out over the whole page and back.
* **Text was what a pinch cost.** Taken away, the page's text halved what a
  frame of a pinch took to draw; the pictures, PDF pages and ink made no
  difference. Scaled at every frame, every letter of it is drawn again at
  its new size.
* On battery, every frame cost three times what it did plugged in — the same
  for the old code and the new.

## Decision

**Text boxes are kept built while out of view.** A text box leaving the
part of the page laid out stays placed, laid out but not painted, pressed
or told to a screen reader (`PlacedOnPage.shown`), up to 64 of them, those
out of view longest let go first. Shown again, it is there at once.
Pictures and PDF pages are let go as before: kept, they would keep what
they have drawn, and they are drawn from what is shared anyway (ADR 30).

**Text boxes about the view are built ahead of it.** Once the view has
rested 300 ms, the text boxes within a view across and two up and down of
it are built, unshown, one a frame, the nearest first.

**While the page zooms, a text box is a picture of itself**
(`ZoomSnapshot`): taken at the zoom it rests at, at most 2048 pixels
across, scaled with the page as the ink's tiles and PDF pages are, and the
box drawn sharp again as itself once the zoom rests. The picture is taken
ahead: 400 ms after the box was painted, once the view has stopped moving,
one box every 60 ms, and kept until the box is painted anew. Taken as the
zoom began, the pictures of the page of formulas held its first frame up
by 50 ms. A box not yet pictured is drawn as itself. The pictures together
hold at most 24 million pixels, those painted least recently let go first.
A box with text in the inverse of what is beneath it (ADR 23) is never a
picture: drawn alone, it would show what is beneath as nothing.

## Consequences

On the two pages, the old code and the new run one after the other, twice
each:

| | before | after |
|---|---|---|
| longest frame to build, scrolling the page of formulas | 13–15 ms | 0.5–4.8 ms |
| drawing a frame of a pinch, page of formulas | 4.5 ms | 1.2 ms |
| drawing a frame of a pinch, page of pictures | 3.3 ms | 1.1 ms |
| drawing a frame of Ctrl and the wheel zooming | 2.4–3.0 ms | 1.1 ms |

* Text is softer while it zooms in, as PDF pages and ink already were, and
  sharp again as the zoom rests.
* Up to a hundred megabytes of the graphics card's go to the pictures, and
  the boxes kept out of view take memory of their own.
* What changes in a box while the page zooms — a caret blinking in it — is
  shown once the zoom rests.
