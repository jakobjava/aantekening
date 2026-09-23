# 10. Formulas stored as LaTeX, typed in place in either syntax

**Status:** accepted; supersedes ADR 6

## Context

ADR 6 kept each formula in the syntax it was typed in, Simple or LaTeX, and
never converted between them. In use that turned out backwards. Someone who
switches syntax wants the formula they already wrote shown in the new one,
not an empty box or the other syntax's source. And a store full of Simple
syntax is readable only by this app, while LaTeX is what every other tool
reads.

Editing had its own problem. The preview of a formula being written was
drawn inside its text box, so the box grew around it, it took the box's width
when the box was resized, and on a dark theme it was black on near-black.

## Decision

* **LaTeX is what is stored.** A formula run's `text` is LaTeX, and its
  `math` is always `latex`. `MathStorage.withLatexFormulas` translates older
  Simple-syntax runs when a page opens, and the page is saved that way.
* **Simple syntax is a way of typing.** `LinearMath.toLatex` translates it as
  it is typed; `LinearMath.fromLatex` — a LaTeX reader and a writer for the
  linear syntax — translates a stored formula back when it is opened in
  Simple syntax, or when the syntax is switched. The syntax is a preference
  of the person (`math.syntax`), not of each formula. A formula opened and
  left unchanged keeps exactly the LaTeX it had, so reading it back never
  reformats anyone's LaTeX.
* **Nothing is lost in translation.** LaTeX the linear syntax has no word for
  is written as it is: a `\command` passes through, and anything else goes
  in backticks. Tests translate every Simple example to LaTeX and back and
  require the same LaTeX, and translate real LaTeX both ways and require a
  stable result.
* **Typed in place, previewed beneath.** The formula being edited is shown
  as its source, in the line, in a code face on a tinted, outlined box, and
  typed like the text around it: the arrow keys go in at either end and back
  out, and it is typeset again once left. The box stands on room laid out
  either side of the source — placeholders in the laid-out text that the
  model does not have — so it never covers the letters beside it. While it
  is open the text box holds the source in the chosen syntax, and reports
  the text to the page with the formula as LaTeX, so the page, its history
  and the file only ever hold LaTeX. Beneath the line, outside the box and
  at a fixed size on screen, the formula is shown typeset on white paper,
  with the parser's complaint if it has one, the Simple/LaTeX switch and a
  Done button — nothing else. It appears once the formula has been laid out
  and its place is known, never first somewhere else. A
  panel of its own to type in was tried and dropped: switching between the
  line and a separate field made writing a formula feel detached from the
  sentence it belongs to. Opening a formula brings the ribbon's Math tab
  forward, with structures and symbols to click in; Tab moves between the
  places a structure leaves to fill in.
* The Simple syntax gained matrices (`mat`, `bmat`, `vmat`, `matrix`), column
  vectors (`vec(1, 2, 3)`), `cases`, `set`, factorials and primes.
* **A formula's highlight is part of its LaTeX.** Selecting part of the
  source and using the highlighter wraps it in the syntax's own construct —
  `highlight(…)`, or `highlight(#A8E6B0, …)` in another colour, in Simple
  syntax; `\colorbox{#FFEF9D}{$…$}` in LaTeX, which is how it is stored —
  and with the caret anywhere in one, pressing again takes it off. With
  nothing selected it marks the whole formula, as highlighting a formula
  from the text around it does, so a highlight made either way can be taken
  off either way; there is no second kind kept on the run. A selection is
  whatever the pointer passed over, so it is fitted to a whole part of the
  formula first (`HighlightSource.fit`): widened to whole words, both
  brackets of a pair with their function, and whole highlights, with an
  operator left hanging let go, and checked to read on its own and to leave
  the rest reading as before — marked as it was, half a formula left empty
  boxes behind. The colour is the highlight as it looks on the white paper,
  since LaTeX's colours are opaque. The source being typed shows what each
  highlight marks on its colour, inside the formula's box, with the
  selection drawn over it; the typeset formula and its preview show it too.
  Two things about the typesetter are put right on the way to the screen
  (`MathView.typesetHighlights`): it paints a colour box only where the box
  has a border, so a highlight is given one in its own colour, and TeX sets
  the `$…$` inside a box in text style, so that style is left out and the
  marked part keeps the size it has around it.

## Consequences

* Switching syntax is lossless for anything typed in Simple syntax, and for
  LaTeX it may respell but renders the same.
* Search indexes the LaTeX. Searching for `sqrt` finds nothing; searching for
  `\sqrt` does.
* The source is part of the line while it is edited, so the box widens with
  it, as it does with words; the typeset formula is usually narrower once
  finished.
* Selection, the clipboard and input methods inside a formula go through the
  text box's own editing, which confines them to the source while it is
  open.
