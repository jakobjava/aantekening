# 26. A caret placed on the paper

**Status:** accepted; revises how ADR 8's text boxes begin and end; a caret
takes no presses, and one a formula is begun at shows as a box, since ADR 33

## Context

A click on empty paper places a caret there, as in OneNote: an empty text
box that shows nothing until something is typed. That box was an element
like any other, and several parts each guessed whether it was "only a
caret". The page guessed from its text, and the box kept its own flag of
whether it had held something. Ending typing reported the box's text while
the page rebuilt, and the empty box was removed a frame later.

Each guess went wrong somewhere. A formula begun with Ctrl+M counted as
something written. Left again, the box kept its move band round nothing.
Text reported during a rebuild changed the page while it could not redraw,
so handles stayed on screen for a box that was gone. Edits to the empty box
were recorded in history, so undo could bring back an invisible box that a
drag or Ctrl+A would then pick.

## Decision

**The page alone knows which boxes are a caret placed** (`_placed` in the
page editor). Such a box:

* shows no band or outline (`TextBoxEditor.caretOnly`);
* is picked by nothing: a drag across it leaves it out;
* is kept out of history and never saved;
* becomes a box with the first thing written in it. The box is recorded as
  arriving then (`CanvasController.replacePlaceholder`), so undo takes it
  back whole, never to an empty box. Undone while it is still being typed
  in, it is a caret again where it was.

**A formula begun and nothing written in it is nothing**
(`TextBoxEditor.isEmpty`).

**Typing ends at once, outside any rebuild.** The page has the box finish its
open formula and report its text (`finishEditing`). It then knows what the
box holds, and removes an empty one in the same step. Nothing is reported
from a rebuild, and nothing waits for the next frame.

A box whose text was all deleted is not a caret placed: it keeps its band
while it is typed in, and goes when typing ends. Undo then brings back what
it last held.

## Consequences

* Whether a box is a caret placed is decided in one place, not guessed from
  its text by each part that needs it.
* What the page does as typing ends is done by the time `_stopEditing`
  returns, so what follows it — Ctrl+A, a paste in place of the caret — needs
  no post-frame callback.
