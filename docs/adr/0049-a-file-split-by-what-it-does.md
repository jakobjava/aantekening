# 49. A file split by what it does, not by its length

**Status:** accepted; follows ADR 34

## Context

ADR 34 split the largest widget states into parts, each one concern of
them. Since then other files have grown past a thousand lines: the notes
folder's mirror, the picker, an AI session, the podcast, the canvas's
controller. Some are long because they hold several things — the mirror
writes, reads, keeps both versions of a page and watches the folder; the
picker works out its rows, maps its keys and carries out its actions —
others, Hunspell's checker and suggester, because they are one thing ported
as it is written.

A limit on length that fails the check would split the first kind where the
count runs out rather than where one thing ends and the next begins, and
the second kind for no gain.

## Decision

**A file is split by what it does, as it is worked on.** Past about eight
hundred lines, a file holding more than one thing is a candidate: each part
one concern, as ADR 34 divides a state — a `part` of the library where the
parts share private state, a library of its own where they need not.

**The check names the long files and fails nothing.** `dart tool/check.dart`
lists the files of code past a thousand lines after its analysis, as a
reminder; files long on purpose, Hunspell's checker and suggester, are left
off the list.

**Tests are not counted.** A test file is many small tests, each by itself,
and is as long as what it covers.

## Consequences

* The list is a reminder, not a gate: a change is never held up by it, and
  a file on it is split when a change to it would be easier to make so.
* A model whose methods are its public API — the canvas's controller, the
  editing of rich text — stays whole, as ADR 34 found; a file of several
  things does not.
