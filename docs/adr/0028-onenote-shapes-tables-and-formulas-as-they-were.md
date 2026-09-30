# 28. OneNote's shapes, tables, formulas and Consolas as they were

**Status:** accepted; revises how ADR 23's shapes keep their corners, and
adds to ADR 20

## Context

Pages brought over from OneNote differed from what OneNote showed, in
four ways the person's own notebooks showed:

* **Shapes came out round.** OneNote keeps a shape drawn with its shapes, or
  snapped to one, as a stroke through its corners and nothing else: a
  rectangle is five samples, an arrowhead three. Ink here is smoothed,
  joining samples by curves through the midpoints between them, which takes
  away a hand's jitter — and took a hexagon of seven samples for a circle.
* **Tables wrapped words OneNote did not.** OneNote keeps a column's width
  as the width of its text, its cells' margins and lines outside it; here a
  column's width is the whole cell's. "Insgesamt", 60 units wide in a
  column 65 wide, broke in two, and the table stood taller than it had,
  over what was drawn beneath it.
* **Formulas ran into each other.** Formulas on lines one below the other
  touched where they held fractions, as TeX sets them, and so did the rows
  of a matrix of fractions. Every equation array — `gathered`, which
  OneNote's stacked equations become — showed its source instead, the
  typesetter not knowing it; and the `#` OneNote ends an equation with,
  before its number, was shown as it was.
* **Text in Consolas stood too low, and ran into drawings.** Consolas is
  on Windows only; elsewhere it was drawn in whatever monospaced face the
  system had — on the person's, Noto Sans Mono, a tenth wider, a sixth
  taller a line, and with its baseline a quarter of its size lower. Lines
  broke early, boxes grew over the drawings beneath them, and text typed
  onto a printout's lines sat below them. Measured on 450 boxes typed onto
  printouts, OneNote sets Consolas's first baseline 0.82 of its size below
  the top of its box, where Consolas's typographic ascent and half its line
  gap put it, 0.83; Calibri's, 0.94, where Carlito puts it.

## Decision

**Consolas is drawn to its measure.** Where it is not installed, text in it
is drawn in Inconsolata — the face drawn after it, under the Open Font
Licence — set to Consolas's measure, as Carlito is to Calibri's
(`RichTextStyles.consolasMeasure`): every cell as wide as Consolas's, the
room added to the right of each letter, and its lines as high and their
baseline as low as OneNote sets Consolas's. `tool/consolas_measure.py`
makes it from Inconsolata.

**A corner is kept a corner** when ink is drawn (`StrokeGeometry.
smoothPath`): where the way turns by more than 30° between sides longer
than the line is wide, the line goes straight to the sample and on. That is
a shape, not a hand's jitter, which is smoothed as before. A shape made
here is kept as its corners alone, no longer each twice.

**A column is as wide as OneNote's text and the cells' own inset**
(`TableCell.inset`), which the page format now names: a column's width is
its cells', their text inset that far on either side.

**Formulas keep a little room above and below** — a tenth of their size,
inside the line wherever they are no taller than its text — so a fraction
never touches the one on the line above. An equation's number follows it,
set to its right (`E=mc^2#(1)`), and a `#` with nothing after it is left
out.

**The typesetter is kept in the workspace** (`third_party/flutter_math_fork`,
its latest release, 0.7.4, used through `dependency_overrides`), changed in
two places, each marked where it is made:

* it sets `gathered` as KaTeX does — one column, each row centred and in
  display style;
* rows of a matrix or array taller than its strut are kept 3pt apart where
  they would otherwise meet, as TeX keeps lines apart by `\lineskip`.

## Consequences

* Handwriting drawn with a sharp turn across long, straight sides keeps the
  turn sharp, as it was drawn.
* Pages already brought over keep the narrow columns and the `#` they were
  stored with until they are brought over again; their shapes and formulas
  are drawn anew as they are.
* Where Consolas is installed — on Windows — text in it is drawn in it, set
  as that system sets it; where its baseline falls there was not measured.
* A later release of the typesetter is taken by merging it into the kept
  copy, the two changes with it, not by raising a version.
