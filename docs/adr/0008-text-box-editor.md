# 8. A purpose-built text box editor, with formulas as runs

**Status:** accepted

## Context

A text box has to behave like a OneNote text container: rich paragraphs,
lists, to-dos, pictures and PDF printouts inside it, and — most importantly —
mathematics written in place. Pressing a shortcut mid-sentence starts a
formula on the same line, in the same box, with no separate window.

Flutter's `TextField` edits one flat string. It can show inline widgets, but it
cannot give each paragraph its own indentation, it cannot select across
several paragraphs that are laid out separately, and it has no notion of a
formula as something the caret can enter and leave. The available rich-text
editor packages each bring their own document model, which would have to be
translated to and from the page format on every keystroke, and none treats a
formula as editable text.

## Decision

Build the text box editor directly on the framework's pieces: one
`RenderParagraph` per block for layout, a `DeltaTextInputClient` for the
keyboard and input method, and the pure editing operations in
`aantekening_core` (`RichTextEditing`) for every change.

A formula is a `TextRun` with `math` set, whose text is its LaTeX, and it is
typeset in place of one placeholder character; `BlockView` maps offsets
between the model and the laid-out text. The formula being edited is laid
out as its source instead, character for character, and typed in place, with
a typeset preview beneath it (ADR 10).

Pictures and PDF pages inside a box are blocks of their own (`TextBlock.embed`)
referring to the asset store, exactly as free-standing image and PDF elements
do.

## Consequences

* The editor works on the page format's own model. There is no second
  representation to keep in step, and the operations — Enter continuing a
  list, Backspace unwinding one, paste joining its ends — are unit-tested
  without a widget.
* A formula shares the text's undo, and is reached from it by keyboard:
  arrowing into one opens it, arrowing off either end returns to the text,
  and Backspace after one selects it before deleting it, so a formula is not
  lost to a stray keypress.
* The editor owns work a stock text field would have done: caret movement,
  mouse selection, IME composition, clipboard. It also owns the touch
  conventions still missing on phones (see the roadmap).
* Editing a formula as typeset maths, rather than as source with a preview,
  remains possible later on the same runs.
