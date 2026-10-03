# 37. A formula typeset in its place, its source beneath; and TikZ pictures

**Status:** accepted; revises ADR 33's preview and source field, and adds to
ADR 36; how a picture is kept is revised by ADR 39

## Context

The formula being edited was typed over its own place (ADR 33): its source
covered the line, and the formula was typeset in a preview beneath it, a
panel of its own, placed on screen, sized to the source and moved with it.
What the formula would look like was shown somewhere other than where it
would be, and the preview was a second, floating thing to place, size and
keep from jumping.

Notes in mathematics and the sciences draw with TikZ: graphs of functions,
geometry, diagrams of nodes and arrows. A LaTeX document brought in lost
its pictures, and a formula could not be one.

## Decision

**The formula is typeset in its place as it is typed**, outlined, at the
size it will have, so what is typed is laid out as it will be once
finished. Its source is typed in a strip just beneath the formula's line,
as wide as the box, over the lines below rather than pushing them down
(`FormulaLayer`, drawn over the page as before). While the source does not
typeset — a bracket still open, a command half typed — the formula stays as
it last typeset (`MathView.problemIn`), and the strip says what is wrong
beneath the source. A source longer than 80 characters is typed in a
window of its own instead (`showFormulaWindow`), a dialog as Insert LaTeX
is, the formula still typeset in its place behind it and outlined: across
a narrow box, a long source would wind down it as a long, thin strip, hard
to read and to edit. It goes back beneath the line only once it is shorter
than 60 (`FormulaWindow`), so it does not go back and forth while it is
about as long as the limit. A source on more than one line is typed in the
window however short: beneath the line Enter finishes the formula, so its
lines could not be kept, and LaTeX brought in keeps how its pictures and
environments were laid out (ADR 38). There is no preview: the Math tab's switch and its
Finish button, and Enter and Esc, do what its buttons did. A click on the
formula while it is open keeps it open, the caret where it was.

**A formula can be a TikZ picture** (`TikzPicture`, in the maths package):
a `tikzpicture` environment or a `\tikz` command. What is read is the part
of TikZ notes are drawn with — paths and their operations, nodes, scopes,
`\foreach`, styles, colours, lines, tips, shading and transformations,
listed in the guide — worked out into paths and the labels of nodes, in
points, as in ten-point type, and drawn at the size of the text around it
(`TikzView`). A node's text is typeset as LaTeX. Where the lines of a path
meet a node depends on how large its label is, so a picture is worked out
twice: once to know what its labels say, and again once they are laid out.
Anything outside this part of TikZ is reported as the picture's problem,
not drawn wrongly.

**A picture is typed as LaTeX**, whatever syntax is chosen: Simple syntax
has nothing to say about TikZ. The switch shows LaTeX while one is open,
and switching waits until it is finished.

**LaTeX brought in keeps its pictures** whole, as formulas on lines of
their own, with the styles the document sets for them (`\tikzset`,
`\tikzstyle`) put first among each picture's options.

## Consequences

* The text after a formula moves as the formula grows while it is typed:
  it is where it will be. The source strip still moves nothing.
* The centring a `#` gives a formula alone on its line is the formula's:
  finishing it takes the caret on to the line beneath, a new one at the
  end, and text typed beside it or a line broken off it goes back where
  lines start. There is nothing else to set a line's alignment with.
* A picture is as wide as it is drawn; one wider than its line is made
  smaller, as any formula is.
* Libraries beyond what is listed — `calc` beyond partway points and
  sums, `intersections`, `decorations`, `matrix`, `pgfplots` — are not read;
  such a picture shows its source and what stopped it.
