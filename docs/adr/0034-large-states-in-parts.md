# 34. Large states kept in parts, by what they do

**Status:** accepted

## Context

A few widgets had grown to hold most of what the app does in one file: the
text box's state was nearly 3,900 lines, the page editor's and the canvas's
nearly 1,900 each, the ribbon's items 1,700. Each was already divided into
sections, but a section was only a comment, and a change to how a formula is
typed meant finding one's way through the clipboard and the pointer to it.

Dart has no partial classes. A `State`'s fields have to be declared in its
class, and `setState` may be called only from the class or its subclasses:
an extension on the state, the usual way to move methods elsewhere, cannot
call it.

## Decision

**A large state is one library of several files** (`part`), each file one
concern of it, written as a private extension on the state: typing,
formulas, the pointer, the keyboard, movement, layout, the menu and the
view for the text box; storage, text, media, the clipboard, commands and
elements for the page editor; the pointer, gestures and hover for the
canvas. The class keeps its fields, its lifecycle, the methods it overrides
and `build`. A file's constants and helpers live in it, as statics of its
extension or private functions of the library.

**`_update(change)` is the state's one wrapper of `setState`**, for the
parts to rebuild it through.

**What stands on its own is a class of its own:** the caret's blinking
(`CaretBlink`), counting clicks (`ClickCounter`), which edits share a step
of undo (`UndoSteps`), and the text box's connection to the input method
(`TextBoxInput`), which the box configures with what the input method sees
and how its edits are applied, rather than being the input method's client
itself.

Widgets that are only a ribbon's buttons, menus and galleries are `part`
files of the ribbon's library, as they were private classes in it.

**The lints are stricter**, where a rule finds mistakes rather than taste:
futures dropped without `unawaited`, constructors that could be `const`,
arguments that repeat a default, classes with value equality not marked
`@immutable`, and the like.

## Consequences

* The longest files left are models, each of one thing, whose methods are
  their public API: the canvas's controller, the editing of rich text, and
  Hunspell's checker and suggester, ported whole and kept as Hunspell has
  them. Splitting them would mean public extensions, or renaming every call,
  for no gain in what they are.
* A part is not a library: what it declares is private to the state's
  library, as before, and it can reach every field of the state. The
  division is one of reading, not of access.
* An extension's static members are named through the extension from
  elsewhere in the library, so a constant used by two parts is a private
  function or constant of the library instead.
