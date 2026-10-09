# 30. Every frame cheap, and PDF pages that never go blank

**Status:** accepted; revises how ADR 21's page is drawn, and how ADR 27's
page follows a zoom; its ink drawn sheet by sheet on pages, by ADR 32

## Context

Measured with a benchmark of its own (`app/aantekening/benchmark`): a page
of eight printouts written over in pen and highlighter, scrolled by a
wheel and a touchpad, pinched and zoomed with Ctrl and the wheel, in a
profile build on a laptop's 2× screen under KDE on Wayland.

* **A frame cost 15 ms of processor time with nothing in it moving.**
  Flutter's renderer, Impeller, keeps nothing between frames, on Linux and
  Windows alike: every stroke on screen was drawn again, its outline and
  all, at every frame of a scroll — 6 ms of drawing a frame on that page.
  GTK filled the window black and painted its background beneath the page
  at every frame before covering both, a fifth of the rest.
* **Every step of a scroll repainted the whole window.** Moving on by a
  quarter of the view builds the page's layers again inside the canvas's
  layout builder, which lays the builder out again; with nothing to stop
  it, that painted the ribbon, the tabs and the sidebar again too.
* **Where every part of the page was, for a screen reader, was worked out
  at every frame of a scroll:** a quarter of each frame's work, as GTK has
  the screen reader's tree built whether one listens or not.
* **PDF pages flashed while zooming.** Zoomed in far, a page is drawn in
  tiles over the whole of it. A new zoom took the tiles away at once and
  asked for new ones, and the page showed blurred, or blank where it had
  just come into view, until they were drawn; zooming out drew the pages
  the zoom uncovered for the zoom it began at, the largest tiles of all. A
  page drawn whole could be 4096 pixels wide: a hundred megabytes, and
  frames as long as a tenth of a second handing it to the screen.

## Decision

**Ink is kept as pixels while the view is not zoomed in on it**
(`InkTiles`): in tiles of 512 device pixels on a grid fixed to the page,
each drawn once from the strokes over it and again only when those change,
or the zoom does. A frame of a scroll draws a picture of each tile. The
page moves by whole device pixels (`PageSpace`), from a corner a whole
number of them from the page's (`pageRegion`), so a tile lands on the
screen's own pixels and looks as the strokes would. Zooming out, the tiles
are shrunk with the page, and drawn again for the zoom it has come to each
time it outgrows them; ~~zooming in, the strokes themselves are drawn until
the zoom stops, sharp at every step.~~ zooming in, the tiles are scaled up
with the page, and drawn sharp again once the zoom rests, as PDF pages are.
Of the tiles needed again, those in view are drawn at once and two more
each frame after, so the thread drawing the frames is never held up by a
whole row of them.

**The canvas is a repaint boundary,** so the page built again repaints the
page alone.

**Where the page's parts are is told to a screen reader once the view has
rested** for 150 ms, not at every frame.

**PDF pages are drawn from pictures shared by every view of them**
(`PdfRasters`), never blank once drawn:

* A view asks for the pictures it needs, and keeps them while it shows
  them; a picture none wants is kept a while longer, those wanted least
  recently let go first beyond 48 million pixels. One that nobody wants any
  more is called off before it is begun.
* It draws whatever it has nearest to what it asked for, at once — the
  whole page as sharp as it is, the tiles drawn coarser before beneath
  those drawn since — so a new zoom sharpens a page rather than flashing
  it, and a page scrolled back to is there in its first frame.
* A new zoom is drawn for once it has rested; while the view zooms, a page
  coming into view is sketched small, and nothing more is asked for.
* A whole page is drawn at most 2048 pixels wide; seen wider, the tiles of
  it about the view are drawn as well, each 1024 pixels square.

**GTK paints nothing beneath the page:** the view's background and the
window's are left unpainted, since every frame covers them.

## Consequences

On the benchmark's page, before and after:

| | before | after |
|---|---|---|
| a frame with nothing moving | 15 ms | 7 ms |
| drawing a frame of a scroll | 5.7 ms | 2.3 ms |
| processor while scrolling with a touchpad | 790–840 ms a second | 500–520 ms a second |
| processor while scrolling with a wheel | 675–710 ms a second | 390–430 ms a second |
| late frames in a three-second pinch | 43–53 | 11–24 |
| late frames zooming with Ctrl and the wheel | 4–40 | 3–6 |
| memory at most | 690–730 MB | 440 MB |

Zooming in and out over a printout in steps, the share of the page that
is printed on never drops from one frame to the next; before, it fell by a
quarter for two frames at a time as tiles went and came back.

* A tile costs memory a stroke does not: about four megabytes of the
  graphics card's for each 512 pixels square with ink on it, about a view
  and a half's worth about the view.
* ~~Zooming in on a page dense with handwriting still draws every stroke at
  every frame of the zoom, as it must to stay sharp.~~ On a page of nearly
  four thousand handwritten words, that took 18 ms a frame to draw, and
  most frames of a pinch were late: ink is soft for as long as a zoom in
  lasts instead, and a pinch has 9 late frames in 180 rather than 100 in
  140.
* A stroke's shape is worked out once, the first time it is drawn; on such
  a page, scrolling onto strokes not yet drawn took up to 30 ms a frame.
  The page's ink is recorded ahead (`InkAhead`), a few milliseconds at a
  time while nothing moves, the nearest the view first.
* GTK's own work for a frame — copying it into the window — is still about
  half of what a frame costs on Linux, and nothing in the app can change
  it: fewer frames are what saves it.
