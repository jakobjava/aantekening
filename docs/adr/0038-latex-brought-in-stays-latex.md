# 38. LaTeX brought in stays LaTeX, with its packages; a preamble of one's own

**Status:** accepted; adds to ADRs 10, 36 and 37

## Context

Every formula could be switched between Simple syntax and LaTeX, which
works because Simple syntax has words for what the typesetter reads. LaTeX
brought in from documents uses more: physics, mhchem and siunitx above
all, and TikZ. Giving Simple syntax words for each package would be a
second language per package, for little gain: what was written in LaTeX is
edited in LaTeX.

And a person writing many formulas defines the same commands in each, or
does without.

## Decision

**A formula brought in as LaTeX is marked so** (`TextRun.imported`, stored
as `"imported": true`), by Insert → LaTeX and by importing `.tex` files.
It opens as LaTeX whatever syntax is chosen, as a TikZ picture does (ADR
37); the switch shows LaTeX while it is open. A formula typed here can
still be switched both ways.

**A formula on lines of its own keeps how it was laid out**: its line
breaks, and how far each line is indented beyond the least indented, so a
TikZ picture or an `align` reads in its window (ADR 37) as it did in the
document. A formula within a line has its spaces run together, as TeX
reads them.

**Only formulas brought in read physics, mhchem and siunitx**
(`LatexPackages`, in the maths package, `MathView.packages`). They are
always on; there is nothing to turn on or off. Each command is written out,
before typesetting, as the LaTeX the typesetter reads — `\dv{f}{x}` as a
fraction, `\ce{SO4^2-}` as upright letters with scripts, `\SI{9.81}{\metre
\per\second\squared}` as a number, a thin space and units — reading its
arguments as the package does, `\qty(…)` and `\mqty[…]` included. The
units siunitx gives, which the typesetter had read in every formula (ADR
36), are read only here now, and Simple syntax no longer takes them whole.
cancel is not among them.

**A preamble of one's own** (Settings → Formulas) holds `\newcommand`s,
`\DeclareMathOperator`s, `\def`s and `\tikzset`s that every formula is
typeset with (`MathPreamble`). It is read as a document's preamble is
(`LatexPreamble`, in core, shared with the LaTeX importer): commands are
written out where they are used, and TikZ styles put first among a
picture's options. What it holds besides is shown as not read. A command's
optional first argument (`\newcommand{\c}[2][x]{…}`) takes what is in
brackets where it is used, and its default where nothing is. What a formula
or picture defines itself is written out the same way before it is drawn
(`MathView.prepared`).

## Consequences

* A formula brought in keeps its mark when it is edited, copied and
  pasted; one typed here never gains it.
* A command physics and siunitx both define, `\qty`, is siunitx's with two
  braced groups after it and physics' otherwise, as documents loading both
  mostly mean it.
* A formula's LaTeX names commands of the person's preamble; copied to
  another machine without that preamble, it shows what it cannot typeset.
