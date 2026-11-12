# 51. The whole app measured, and what moves moved cheaply

**Status:** accepted; follows ADR 30, ADR 42 and ADR 45

## Context

The canvas's benchmark (ADR 30) measures a heavy page scrolled and zoomed.
Nothing measured the rest: starting, opening pages, writing, typing,
picking and dragging, searching, the picker, the library. What was slow
there was guessed at from reading the code.

## Decision

**A second benchmark drives the whole app** (`benchmark/app_benchmark.dart`)
on notes it makes up — two thousand pages, a few of them far heavier than
any written by hand — kept in a temporary folder: nothing of the person's
notes, settings or keys is read or written. It presses real keys and moves
a real pointer and pen, in a window of its own for each start, and writes
every number to a file two runs of which `benchmark/compare.dart` sets
side by side. Run before and after, plugged in, a change is shown to have
helped; two runs of the same code say how far the numbers wander.

Its first runs found the frames below, and each was mended where it was
made, not hidden:

**A text box's rows go with their blocks.** Keys and built rows were kept
by where a block stood, so a line begun near the top of a long box built
every paragraph below it again: 48 ms a frame for four hundred. They are
now put in and taken out after what changed between the blocks unchanged
at the start and at the end, and the framework moves the rest: 3 ms. What
belongs to the caret alone — which side of a line's end it is on, the size
it is drawn at for what is typed next — no longer counts for the rows
without it.

**Ink only moved is not made again.** At each step of a drag every sample
of the ink dragged was copied and moved, every stroke's shape worked out
and recorded: 24 ms a frame, after 5 ms a step, for a page of three
thousand strokes all picked. An `InkElement` moved knows what it was moved
from and how far, back to ink whose strokes were drawn, in one step
however many the drag took. It is drawn as that ink's picture, moved; its
bounds are that ink's, moved; and its strokes are moved when first asked
for, which a drag never does: 4 ms a frame, after 1 ms a step. What it was
moved from is kept while it is, as undo keeps it anyway.

**Glass grows within its frost.** A pane floating in grows the last
little way to its size. Grown as a whole, its frost was laid at a new size
each frame, and its words set at a new size with it, each new to the
renderer: 18 to 45 ms a frame for the first pane of a session. The glass
now grows itself — fill, rim, shadow and what is on it — inside frost
laid at its full size from the first, and what is on it is a picture
(`SnapshotWidget`) until it has come: 2 ms a frame.

## Consequences

* What the benchmark's heaviest pages cost is not what a person's cost: a
  page of three thousand long strokes takes 200 ms to read, eight times
  the largest page of the notes these were first run beside. Reading a
  page was left as it is.
* The tiles a drag crosses are still drawn again at each step; on a page
  of thousands of strokes all dragged at once, two frames in five take
  longer than one. Kept as the picture they were, and moved, they would
  not be.
* A pane of glass inside a pane floating in is, for that quarter of a
  second, part of its picture, and frosts nothing.
