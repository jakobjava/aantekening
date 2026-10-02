# 35. Formulas and tables of earlier builds read as text boxes

**Status:** accepted; revises how ADR 10 and ADR 15 treat the elements of
earlier builds

## Context

Builds before 0.1.0 put a formula, or a table, on the page by itself, as an
element of its own (`math`, `table`), and the page format had a `group`
element that nothing ever made. Formulas and tables have long been written
in text boxes (ADRs 10 and 15), but each of the old kinds kept a class, a
way of being drawn, resized and summarised for the AI, a case in every
switch over elements, and, for a formula, a double-click that turned it
into a text box. None of it was reached by anything made since.

Taking the kinds out of the format outright would have dropped them from
pages that still hold them, silently, the next time such a page was saved.

## Decision

**Reading a page turns them into what holds them now** (`NoteElement.
fromJson`): a `math` element becomes a text box holding the formula, its
text where the formula was; a `table` element a text box holding the table,
each cell a table cell of the box, with the widths its columns had; a
`group` is left out, its members staying where they are. The page is
written in the new form the next time it is saved.

The classes, their drawing, their resizing and their double-click are gone.

## Consequences

* A page from an early build opens with its formulas and tables editable at
  once, rather than after a double-click or never.
* A table's header row is no longer shaded: it is a row like the others.
