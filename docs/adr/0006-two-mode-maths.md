# 6. Two maths modes, and no conversion between them

**Status:** superseded by [ADR 10](0010-latex-stored-formulas.md). Formulas
are now stored as LaTeX and translated both ways; the parser described here
is unchanged and does the Simple-to-LaTeX half.

## Context

Maths is a first-class requirement. LaTeX is precise but slow to type in a
lecture; OneNote-style linear input is fast but cannot express everything.

## Decision

Support both. Store the source in the mode it was authored in and translate
linear input to LaTeX only at render time, through a real lexer and
recursive-descent parser. Never rewrite one mode's source into the other.

## Consequences

* Switching a formula's mode back and forth cannot degrade what was typed,
  because nothing is ever round-tripped.
* Precedence, nesting and bracket elision behave predictably — `(a+b)/c`
  becomes a clean built-up fraction, `sum_(i=1)^n` keeps both limits, and
  `sin(x)/x` keeps the function application in the numerator. Regular-expression
  substitution gets all three wrong.
* The parser never throws: a half-typed formula yields a placeholder plus
  diagnostics, so the live preview keeps rendering while you type.
* Both the source and its diagnostics are testable without a running renderer,
  and the test suite additionally parses every generated expression with the
  real TeX engine, so plausible-looking output cannot pass.
