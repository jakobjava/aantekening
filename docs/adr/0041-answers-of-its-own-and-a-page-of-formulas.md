# 41. Answers of its own, and a page of formulas that scrolls

**Status:** accepted; revises how ADR 17's AI answers and ADR 25's study
sets are asked for, how ADR 23's highlighter is blended, and how ADR 30's
page paints and is told to a screen reader

## Context

With every school note moved into the app, four things stood out:

* **The AI only copied the notes.** Asked a question, it answered at
  length, headed and listed, and often added flashcards nobody asked for.
  Its summaries went through the notes in their order, taking every
  formula along — a derivation's every step, each worked example's
  numbers. The system prompt put the notes first and told the model to
  say what they say; and it described the flashcard format in every
  conversation, which the model took as an invitation.
* **The highlighter filled the screen with yellow on Windows**, or drew a
  stroke the whole width of it. It was multiplied with what lies beneath
  (`BlendMode.multiply`), one of the blends Impeller does by reading back
  what is drawn beneath into a texture of its own; on Windows that went
  wrong.
* **A page of formulas laid over printouts scrolled with hitches.**
  Measured on a physics page of forty boxes of formulas over three PDF
  pages: thirteen late frames in a wheel's scroll. Placing what comes into
  view painted the page's element layer again, and with it every box
  already there — a formula is a few hundred boxes of its own, a glyph
  each, painted one by one. And every glyph was a node for a screen
  reader, worked out again whenever the page rested.
* **A click on one box's text could open another box.** A box is wider
  and taller than its text: a box holding a letter is as wide as the
  narrowest box, 80 units, and its paper lies over the next box's words.
  The topmost frame took the click.

## Decision

**A question is answered, briefly, and backed by the notes.** The model
answers as someone who knows the subject, then supports what it says with
the notes, in their own words and notation, cited. It gives the answer
alone, in as few words as make it clear, with nothing unasked: no
flashcards, quiz, practice questions or tips. What the notes say is still
cited and kept apart from the web; what the model knows itself cites
nothing. The flashcard and quiz formats are for when they are asked for.

**Study sets reorganise the notes in their own words.** They follow the
subject rather than the order of the notes, bring together what belongs
together and say once what is said twice, reusing the student's phrases,
which are easier for them to remember. A summary's formulas are the few to
know by heart and apply, rarely more than five — never a derivation's
steps, a worked example, a formula with numbers put in or one rearranged.

**The highlighter multiplies by `BlendMode.modulate`.** Its colour is laid
on white first (`InkPainter.onWhite`) and drawn opaque: over anything
opaque that gives exactly what multiplying the translucent colour gave,
and modulate is one of the blends a GPU does as it draws. Its layer, kept
as pixels, is drawn on white for the same reason, rather than on nothing.

**Each element is painted once, in a layer of its own** (a
`RepaintBoundary` about every placed element). Placing what comes into view
paints that alone; what was there is drawn from the layer it was painted
in.

**A formula is one node for a screen reader,** read as its source, its
glyphs left out.

**A box is pressed on what it holds** (`PlacedContent`). A text box says
where its lines, list marks, pictures and tables are. A press on its
paper goes to the text of a box beneath, if there is text there before
anything that is pressed all over its frame — a picture, a PDF page, ink —
and to the topmost box otherwise, as before, so a click just past the end
of a line still lands in its box. The canvas's widgets and its controller
(`CanvasController.hitTest`, which picks, hovers and offers menus) decide
alike.

## Consequences

On the physics page, scrolled with a wheel in the benchmark, which can
now open a copy of a notes folder (`AANTEKENING_BENCH_NOTES`) and reads
down a page as well as flicking through it:

| | before | after |
|---|---|---|
| late frames, wheel | 13 | 4–7 |
| a frame, on average | 10.2 ms | 6.4–7.0 ms |
| building a frame, 90th percentile | 5.3 ms | 1.5–1.8 ms |
| late frames, pinch | 42 | 11–13 |

* What is left is typesetting a box of formulas the first time it comes
  into view — up to 30–40 ms for a long derivation. Placing what lies
  about the view a few elements a frame, while the page rests, was tried
  and measured no better; a formula kept as a picture once typeset would
  be the next step.
* A layer for each element costs a little memory for the pictures kept,
  and nothing while nothing changes.
* A screen reader reads a formula as its LaTeX.
* The answers depend on the model following its instructions; a small
  local model still runs long.
