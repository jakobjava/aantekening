# 9. A ribbon of tabs, arranged by the person using it

**Status:** accepted

## Context

The editor had a single toolbar row, and a second row of text formatting that
floated over the page while a text box was being edited. The second row came
and went with every click, so the controls were never where the hand expected
them. The app is modelled on OneNote, whose commands sit on a ribbon: tabs of
related commands in named sections, always in the same place.

People arrange their tools differently, and a fixed arrangement serves the
median user. Moving a button should be as direct as dragging it, not a
settings dialog.

## Decision

Replace both rows with one ribbon above the page:

* **Tabs.** Home (undo, font, paragraph, styles, formula), Insert (text box,
  pictures, PDF printouts, formula), Draw (tools, pens, colour, thickness),
  Math (syntax, structures, symbols; see ADR 10) and View (zoom, the ribbon
  itself). Each tab is divided into sections by vertical
  lines, each section named beneath it. Tall buttons take a column; small ones
  stack two to a column, as on Office's classic ribbon, so Home fits a
  700-pixel editor. A narrower window scrolls the ribbon sideways.
* **Always there.** Commands with nothing to act on are greyed out rather than
  hidden. With a text box *selected* rather than being edited, the formatting
  commands apply to the whole box (`BoxFormatting`), as in OneNote.
* **Follows the tools.** A tool's shortcut brings its tab forward: P, H and E
  show Draw, V or T show Home, and opening a formula shows Math until it is
  finished. Clicking a tool on the ribbon leaves the tab alone.
* **Rearranged by dragging.** Any button can be dragged to another place,
  section or tab; holding it over a tab's name opens that tab. A mouse drag
  starts after six pixels, so a click with a wobble is still a click, and a
  finger starts one by holding, so a swipe still scrolls the ribbon. Sections
  are fixed; only buttons move. `RibbonLayout` keeps every button in exactly
  one section, so nothing can be lost or doubled, and reads a saved layout
  leniently: unknown names are dropped and buttons added in later versions
  appear where they start out. (The sidebar's buttons have since come to be
  arranged the same way, by the same code; see ADR 11.)
* **Never takes the focus.** The ribbon sits inside `ExcludeFocus`, so pressing
  Bold leaves the caret — and the input method's connection — in the text it
  formats.

The layout, and whether the ribbon is collapsed, are saved in a small
`preferences.json` beside the workspace rather than in it: they belong to the
person on this machine, not to the notes, and copying a workspace should carry
notes and nothing else.

## Consequences

* The ribbon is taller than the old toolbar. Ctrl+F1 or the arrow at its right
  folds it down to the tab names; clicking a tab opens it again.
* Keyboard users reach commands through their shortcuts, not through the
  ribbon, which has no Alt key tips yet.
* The page editor no longer rebuilds when the view moves. Each ribbon button
  listens for just the value it shows, so scrolling repaints the canvas and
  nothing else.
