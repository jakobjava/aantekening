# 18. One colour, words, straight edges — and the keyboard

**Status:** accepted — revises the look of ADRs 9 and 11

## Context

The interface was Material's: a blue seed colour tinting every surface,
Google's icons on every button, rounded corners, shadows under what floats,
ripples on every press, and a different colour for each kind of study set,
each grade of a flashcard and each origin of a citation. Settings lived
where they were first needed — the AI's in a dialog of its own, the
spelling dictionaries in a ribbon menu — and there were none for how the app
looked. Shortcuts were written into tooltips by hand, so a tooltip and the
key it named could disagree, and most commands had none: nothing opened a
page by name, went back, or stepped from page to page.

The person using it wants the opposite of decoration: an interface of one
colour and its text, for focus, that does not hide functions to look
minimal, is square, drops the icons — they are at home in a terminal — and
can be set to their liking, down to its colours; moved about from the
keyboard; and never dressed up to look clever.

## Decision

**Two colours and at most one accent.** The appearance chosen (`Appearance`,
kept in the preferences) gives, for light mode and for dark, a base colour
and a text colour; every other shade — panes, hover, lines, faint and muted
text, the tint of what is picked — is mixed between the two (`Tones`). An
accent is optional; with it, what is picked, pressed in or has the keyboard
is marked in it, and without it in the text's colour. Nothing else has a
colour of its own: study sets, grades, citations and errors are told apart
by words, weight and shape — filled or hollow, boxed or plain — and Material
widgets left to the theme draw in the tones, since every colour role maps to
one. The accent is made to stand out against the base, and a second shade of
it against the white paper, which stays white in dark mode too; the caret,
selection, formula box, search matches, misspellings, links and selection
handles on the page are drawn in that one.

**Words, and a few drawn marks.** No icon font is used. Buttons are their
names; formatting buttons are the letter they format, formatted. The
sidebar's buttons are words written up the strip, as an IDE's tool windows
are. What a word would be too long for — close, add, a chevron, a tick, an
arrow, more — is a `Mark`, drawn in thin straight lines on a twelve-unit
grid, so every mark is of one set.

**Straight, flat and still.** Nothing is rounded and nothing casts a shadow;
what floats has a one-pixel edge. Presses show at once instead of rippling.
A flashcard switches sides instead of turning over in depth.

**Type.** The interface is set in IBM Plex Sans or IBM Plex Mono, bundled so
it looks the same on every platform. Pages keep the platform's own type
(`RichTextStyles.paperType`), so a note reads the same whatever the
interface is set in.

**One control for each job.** `RowTile` is every row that is picked from —
notebooks, pages, search results, the AI's rail, the palette, the settings'
pages; `ChoiceRow` every choice of a few; `CheckRow` every setting that is on
or off; `Swatch` every colour; `Busy` every sign of work; `SmallCaps`,
`KeyHint`, `PaneHeader` and `EmptyMessage` the same wherever they appear.

**A size.** The whole interface, the page with it, is drawn at 90 to 150
per cent, as a browser zooms (`InterfaceScale`).

**Settings.** One window (Ctrl+,) with a page each for the appearance, the
layout, the keyboard, spelling, the AI's models and where the notes are.
Dictionaries are downloaded, added and removed there alone; the ribbon's
Languages menu ticks those installed and opens it.

**Commands.** Every command that can have a shortcut is an `AppCommand`, with
its name, group, what it does and the keys it starts with. Keys can be
changed in the settings; a chord taken by one command is taken from any
other. Whatever carries a command out — the window, the page editor —
registers what it does with `CommandHandlers`, and the keyboard, the
palette and tooltips all go through there and through the one set of
bindings, so a tooltip names the key that works. Chords with Ctrl, Alt or
Meta, and function keys, are caught wherever the keyboard is
(`CommandKeys`); plain keys only while the page has it. A chord that typing
takes — Ctrl+−, strikethrough — reaches its command only through the page,
after a text box has had it, and cannot be given to a command in the
settings. The keys of typing are fixed, and listed in one table
(`EditorKey`) that tooltips and the settings both read.

**Moving about.** Go to (Ctrl+P) opens any page, section or notebook by a few
letters of its name, the pages opened lately first; Commands (Ctrl+Shift+P,
or `>` in Go to) runs any command by name. Alt+Up and Down step through the
pages of a section, with Shift through the sections of a notebook; Alt+Left
and Right go back and forward through the pages a tab has shown; Alt+1–9
shows a tab; Ctrl+Shift+T reopens the tab closed last; Ctrl+Shift+E and
Ctrl+F give the notebooks and the search the keyboard, and the arrow keys go
on from there; Ctrl+N makes a page, F2 renames it, Ctrl+Shift+D switches
light and dark, F1 lists every shortcut.

## Consequences

* A look is a pair of colours and an accent, not a palette to keep in step:
  a new part of the interface takes its colours from `Tones` and cannot
  stray from them.
* The white page in dark mode stays white; drawing notes themselves in dark
  colours would mean mapping every colour written in them, and is left for
  later.
* Words take more room than icons: the ribbon scrolls sideways sooner, and a
  menu's formatting row is drawn smaller where it does not fit.
* The interface's fonts add about 1.7 MB to the app.
