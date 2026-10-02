# 32. Pages: the one paper cut into sheets

**Status:** accepted; adds a second way of seeing ADR 21's page

## Context

A page here is one paper without end, to the right and down, as OneNote's
is. Some notes are better kept as a paper notebook keeps them, as GoodNotes
does: on sheets of a set size, ruled, squared or with staves, one after
another, added to as the notes grow, with a printout put a page to a sheet.
Both should be had of the same page, back and forth, without the notes
moving: a page shown as sheets and shown as one paper again is as it was.

## Decision

**A page is shown as a canvas or as pages** (`NoteLayout`, kept with the
page as `canvas.layout`). Shown as pages, it is cut into **sheets**
(`Sheets`, kept as `canvas.sheets`): A4 or Letter, each printed with a
template — blank, lined, squared, dotted, music staves or Cornell — and as
many as hold what is written.

**The content is where it is either way.** The sheets cut page space into
bands a sheet tall, from its top, one after another without a gap; switching
to pages works out the sheets (`Sheets.fittedTo`) — as wide as the widest
writing, scaled up from the paper with its proportions kept, and as many as
reach the lowest — and moves nothing. Back on one paper, the sheets are
kept, so shown as pages again the page has the ones it had. How the page is
shown is not an edit: it is no undo step, and undo leaves it as it is.

**The view folds the page** (`SheetFold`, carried by `CanvasViewport`). It
lays the bands out one under another with a gap between each; the view pans
and zooms over that laid-out space, and every conversion between the screen
and the page goes through the fold, so hit-testing, the selection, the
marquee and the lasso, writing, erasing, revealing a search match and the
scrollbar work unchanged. In the page's own layer:

* each element is moved whole with the sheet its middle is on, so a box or
  a picture is never torn across a gap; its selection's outline with it;
* ink is drawn sheet by sheet, each part moved down by the gaps above it
  — a whole number of device pixels, so tiles of ink stay on the screen's
  pixels (ADR 30) — and cut at the sheet's edges.

**Sheets lie on a desk, in the middle of the view** while they are narrower
than it. The view stops a little past them on every side, with room below
the last for a button to add another; the overscroll spring and the glide
stop there too (`CanvasController.originRange`, which on one paper is the
page's top-left corner on, without end). The desk, where the pointer shows a
hand, is held to move the sheets: a pen pressed there writes nothing. A line
written off its sheet is cut at the edge rather than drawn along it.

**Sheets are added, moved, taken away and printed** from the Home tab's
Pages section and with Ctrl+Shift+Enter. A sheet added after the one in
view is printed as chosen, as that one is unless another is picked, and
what follows it moves down; a sheet moved takes what lies on it — what has
its middle there, a stroke of handwriting at a time — and the sheets
between make room; a sheet deleted takes what lies on it, and what follows
moves up. All are one remapping of sheets to their new places, and all
undo. What is put below the last sheet adds sheets to lie on.

**A printout asks where it goes**: on new sheets after the one in view, a
page to a sheet; on the page as it is — over the sheets from the one in
view on, or down a canvas; or as a new page of its own, shown as pages and
named after the file, for a book. Each of its pages is as large as its
sheet takes it; on sheets of its own, new or on a new page, it is set as
their background, as a printout written over is.

**A new page is made as one or the other.** New page asks — canvas or
pages, and for pages the template and the size — offering the choice last
made, so Enter makes another such page; a notebook's first page is made as
the last was, without asking.

## Consequences

On the benchmark's page, shown as pages, every measure is as it is shown as
one paper, within what varies from run to run: frames of a scroll in 5–6
ms, the same processor time and the same late frames.

* Where an element straddles two sheets it is drawn on the one its middle
  is on, overlapping the gap; its handwriting, drawn sheet by sheet, is cut.
* Sheets are as tall as their width has them: writing wider than the paper
  makes taller sheets, not more of them.
* A template's lines are drawn fainter the closer they come on screen,
  down to a third of their strength, so sheets seen far off keep their
  pattern without turning grey.
* Sheet sizes and templates are drawn by the app; a template's lines are
  worked out once for a size of sheet and drawn in one call per sheet.
