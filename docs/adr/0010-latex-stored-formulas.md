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
