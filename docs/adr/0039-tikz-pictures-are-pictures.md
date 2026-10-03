# 39. TikZ pictures are pictures in the text, and read much of TikZ

**Status:** accepted; revises how ADR 37 keeps a TikZ picture, and adds to
ADR 38

## Context

A TikZ picture was a formula (ADR 37): clicking it opened its source, and it
could not be made larger or smaller. On the page it is a drawing, and is
used as one: placed, picked, resized. Its source is edited now and then,
and is long enough to want a window of its own, its lines kept (ADR 38).

What notes are drawn with is also more than the core of TikZ: the arrows,
calc, shapes, intersections, angles, decorations, patterns and matrix
libraries, and pgfplots for graphs of functions.

## Decision

**A TikZ picture on a line of its own is an object in the text**
(`EmbedKind.tikz`, `BlockEmbed.source`), as a photo or a PDF page is: a
click picks it, its corners resize it (`width`; 0 while it is as large as
it is drawn, its height always what its drawing makes it), and it sits
where the line's alignment puts it. Right-click → *Edit TikZ source* opens
its source in the window long formulas are typed in (`showFormulaWindow`,
`picture: true`): Enter is a new line there, Ctrl+Enter finishes, and the
picture is drawn again with each change. Emptied, the picture goes.

**On the page by itself it is an element of its own** (`TikzElement`,
`"type": "tikz"`), as a picture or PDF page is: picked, moved,
turned and resized as one, set as the background, and edited from its
right-click menu in the same window, one undo step for the whole edit.
Its frame keeps the proportions of its drawing, which is scaled to fill it:
as its source changes the frame's height follows (`onDrawn`), as a text
box's follows its text, without an undo step of its own. Taken out of
text, it keeps the size it was drawn at there. It goes into text and out
of it as pictures do (`asEmbed`, `toElement`).

It becomes one where it is made: brought in by Insert → LaTeX or a `.tex`
file, typed as a formula alone on its line and finished, and read from a
page that kept it as a formula (`TextBlock.fromJson`), so pages from
before need nothing done to them. A `\tikz` in a line of text stays a
formula, typed as LaTeX.

**The libraries read** are listed in the user guide. Each is worked out
into the paths and labels the picture already draws (`TikzDrawing`), in
part files of `tikz_picture.dart`: node shapes (`tikz_node_shapes`),
decorations and patterns (`tikz_decorations`), intersections, angles
(`tikz_pics`), matrices and pgfplots' axes (`tikz_axis`). A pattern clips
lines or dots to the shape; a decoration replaces the path with the one it
draws, or with marks along it; a matrix and a legend are laid out from
their labels' sizes, as nodes are, in the second of a picture's two passes.

## Consequences

* A picture is never a formula on its own line again: there is no going
  back from the object to a formula but its source, copied.
* pgfplots is read as far as plots in a plane go: `\addplot3` says it
  cannot be plotted, and options it has no use for — `ybar`, `ymode=log`,
  `fill between` — are passed over, the plot drawn as lines.
* Labels are not turned: a `ylabel` stands upright beside its axis.
* The AI reads a picture by its source, not by an image of it.
