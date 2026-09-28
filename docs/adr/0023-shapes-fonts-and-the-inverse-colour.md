# 23. Shapes as ink, fonts, and a colour that is the inverse of what is beneath

**Status:** accepted; adds to ADRs 5 and 18

## Context

Drawing a straight line, a box round a word or a coordinate system for a
graph took a steady hand, or a ruler held to the screen. Text could only be
set in the page's own typeface, though text brought from OneNote kept its
own. And a colour that reads on the white paper does not read on a dark
picture or printout, and one that reads there does not on the paper.

## Decision

**A shape is ink.** As in OneNote, a shape is strokes like handwriting,
not an element of its own: it is picked, moved, resized, turned and erased as
handwriting is, and needs nothing new of the file, the renderers, the AI or
search. A shape is a shape (`InkShape`) only while it is drawn: through
points (`PathShape`: lines, arrows, number lines, and the lines and outlines
recognised) or in a box with axes of its own (`BoxShape`: outlines, graphs
and solids), with handles that reshape it while the pointer is down. It is
kept as strokes of the pen's ink, each corner sampled twice so the smoothing
ink is drawn with passes through it, as an element of its own that writing
after it does not join.

**Held still, a stroke becomes the shape it was drawn as.** Half a second
still at the end of a stroke, the pen down, and `ShapeRecognizer` reads it:
a line if it keeps within a sixteenth of its length of the line between its
ends; an arrow if a head is drawn on after a straight shaft; corners, found
by Douglas and Peucker's simplification and kept where the way turns, joined
by sides that bow little — an outline's by a tenth of their length, since an
ellipse's arcs bow twice that, lines left open by less, since writing is
rarely that straight; four right angles a rectangle, turned if drawn turned;
failing corners, the ellipse that fits best, by the least squares of
(u/a)² + (v/b)² = 1 along its principal axes, if it goes round once. It is
strict: a stroke that is none of these clearly stays as it was written,
since the pen resting at the end of a word must not turn the word into a
shape. What nearly is level, upright, square or round is made so. The pen
then holds the shape by its handle nearest it: a line's far end follows it, a
box's corner moves with the one across from it kept, a polygon's corner
moves by itself — each measured from where the pen took hold, so nothing
drifts. A highlighter's stroke is only ever straightened.

**Shapes to drag out.** The Draw tab's Shapes (S) holds lines, outlines,
graphs — axes, in one quadrant, four or in 3D, a number line and a grid,
ticked every square of the page's grid, the oblique x axis at half the
square's diagonal as a drawing in oblique projection has it — and solids,
their hidden edges dashed. Each is drawn in the gallery from the very lines
it is drawn with on the page. Dragging reshapes as a held stroke does; a
click puts one down at its usual size; Shift keeps a box square and a line to
steps of 15°.

**A colour that is the inverse of what is beneath** (`NoteColors.inverse`),
for text and the pen. It is kept as transparent white, which a build that
does not know it draws as nothing rather than as a colour it never was, and
drawn white, laid on the page by difference: black on the paper, white on
black, the opposite of any colour between. Ink in it is its own layer, over
all the rest (`InkLayer.inverting`), drawn as one so that where strokes
cross the crossing is inverted once, and kept as pixels, as the page's map
keeps it, laid on by difference as well. Text in it is drawn with that
paint; a formula in it is typeset white and laid on the page by difference.
This relies on a layer blending with what was drawn before it, as the
highlighter's multiply already does: Impeller, the renderer on every
platform the app runs on, keeps no pictures between frames that would
blend with nothing.

**Fonts.** The Home tab's Font menu sets text in the page's own typeface,
one the app brings (IBM Plex Sans and Mono, Carlito), which looks the same on
every computer, or one installed — listed by fontconfig on Linux and from
the registry on Windows, and where they cannot be listed, those most
computers have. Each is named in itself. Formatting a run no longer loses
its typeface or script.

## Consequences

* A shape cannot be reshaped by its handles once the pen lifts; it is
  resized and turned as a whole, as handwriting is.
* Shapes are recognised only as they are drawn, not in handwriting already on
  the page.
* A picture of a page drawn for the AI lays its text boxes on the page as a
  picture of their own, where text in the inverse colour has nothing beneath
  it: it is white there. Ink in it is drawn as on the page.
