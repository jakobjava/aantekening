# 36. LaTeX in formulas and notes: amsmath, Simple syntax, and LaTeX brought in

**Status:** accepted; adds to ADR 10. ADR 38 keeps what is brought in as
LaTeX alone, gives it physics, mhchem and siunitx, and moves units there.

## Context

Formulas are typeset by a fork of flutter_math, a port of KaTeX, which
reads much of LaTeX's mathematics but not amsmath's display environments —
`align`, `gather`, `equation`, `multline`, `split` — nor `\tag`, `\notag`,
`\DeclareMathOperator`, `\def`, and a handful more that notes written in
LaTeX use everywhere. `\newcommand{\R}{…}`, at the top of many a
document, failed outright, `\R` being defined already; and two operators
in a row, `\limsup \liminf`, failed too, the first taking the second as
its argument.

Simple syntax passed a `\command` through, but read its braces, and what
followed, as Simple: `\begin{align}` became four letters, the words of
`\text{for all}` were read as variables (and `all` as `\ll`), and a script
after `\mathbb{R}` went inside its braces.

And there was no way to bring LaTeX in that was more than one line: a
formula is typed on one line, and nothing read a passage of text with
formulas in it, or a `.tex` document.

## Decision

**The typesetter reads amsmath, amssymb and mathtools as notes use them.**
Their display environments are set as the environments they are made of —
`align` as `aligned`, `gather` and `equation` as `gathered` — since a
formula here is one equation, numbered by nothing; `\tag{2}` is set after
it, `\label` and `\notag` show nothing. The starred matrices take their
column alignment. `\def`, `\gdef`, `\DeclareMathOperator` and a
`\newcommand` of a command defined already define it; the rest are written
as the nearest the typesetter can set (`ams_macros.dart`). An operator
takes what follows as its argument only where that can be one.

**Simple syntax reads LaTeX among it as LaTeX.** An environment, text and
font commands (`\text`, `\operatorname`, `\mathbb`, …) and labels are
taken whole, as typed; `\left` and the `\big` family take their delimiter.
Any other command takes the groups typed against it as its arguments,
their contents read as Simple — `\boxed{a/b}` is a boxed fraction — and a
script after them is the command's. Shown in Simple, a formula's
environments and text are written as they are, not in backticks.

**LaTeX of any length is read as text** (`LatexText`, in interchange):
paragraphs, `\section`s as headings, lists, tables, bold, italic,
underlining, code and links; `$…$` and `\(…\)` as formulas in the line;
`$$…$$`, `\[…\]` and the display environments as formulas on lines of
their own, centred, each kept whole on one line. What a document defines
is written out where it is used, so each formula stands by itself. What
only sets out a printed page — spacing, page breaks, `\maketitle` — is left
out. **Insert → LaTeX** puts what it reads into the text box being typed
in, or a box of its own; **Import → LaTeX** makes a page of each `.tex`
file, titled as its `\title` says.

## Consequences

* A formula in a table cell is measured before it is laid out, as the
  table sizes its columns; the typesetter cannot say where its baseline is
  until it is laid out, so it is taken as the formula's foot then
  (`ShrinkToWidth`). Asking the typesetter had made any formula in a table
  fail.
* Commutative diagrams (`CD`) are not read; nor is LaTeX's numbering of
  equations, sections or lists: a list is numbered as lists here are.
* A command whose braces hold what is not mathematics, and that is not in
  Simple's list of them, has its braces read as Simple; quoting it in
  backticks keeps it as it is.
