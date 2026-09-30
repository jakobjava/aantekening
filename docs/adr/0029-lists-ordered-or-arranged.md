# 29. Lists ordered, or arranged by hand

**Status:** accepted

## Context

Pages and notebooks were listed only as they were arranged, and arranged
only by cutting one and pasting it after another. A section of forty
lectures could not be listed by date, nor its pages found by name, and
putting a page first took a trip through the menu.

## Decision

**Each list has its order** (`ListOrder`): as arranged; by when each was
made, or last changed, newest or oldest first; or by name, A to Z or Z to
A. The pages' order holds for every section, the notebooks' for all of
them, and each is remembered. **Sort**, in each pane's header, chooses it.

* Subpages are ordered among themselves, beneath their page.
* A notebook last changed when anything in it did: itself, or the latest of
  its pages (`LibraryRepository.notebookChanges`).
* Names are compared as a person reads them: whatever their case, their
  accents left off, and numbers by their value — "5.3" before "5.10".
* Items that tie keep the order they were arranged in.
* What is shown is what the keyboard steps through: the order is applied
  where the lists are read, not only where they are drawn.

**As arranged, rows are dragged into place** (`ArrangeableRow`): a page or
notebook dragged over another goes above it or below it, as the line drawn
there shows, a page as that page's sibling — never among its own subpages.
Arranging is no change to what is arranged (`arrangePage`,
`arrangeNotebook`), so it does not move it in a list ordered by when things
changed. Sorted, rows are not dragged.

A mouse, a pen or a touchpad drags them; a finger drags the list, as it
does any list, and arranges by cutting and pasting.

## Consequences

* Positions are shared by every order: sorting changes nothing stored, and
  going back to the arranged order finds the list as it was left.
* A page changed while its section is listed by when pages changed moves
  to the top as it is saved.
