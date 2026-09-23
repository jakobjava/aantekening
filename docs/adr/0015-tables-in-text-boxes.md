# 15. Tables in text boxes, as lines of cells

**Status:** accepted

## Context

OneNote makes a table as it is typed: a word and Tab start one, Tab and
Enter grow it, and every cell holds rich text as a paragraph does. Here a
text box is a list of blocks, and everything that works on text — the caret,
selection, formatting, formulas, spelling, search, copy and paste, undo —
addresses a place in it as a block and an offset (ADR 8). The page format
had a free-standing `TableElement`, drawn but never edited, whose cells are
not blocks of a box at all.

A table as a block holding a grid of blocks would be the obvious model, but
every operation, and every place a position is taken apart, would then need
a path into the grid, and each would need teaching to walk it.

## Decision

* **A table is a run of blocks, each naming its cell** (`TableCell`: row,
  column, and the column's width), in reading order — as Word keeps a table,
  as paragraphs ending in cell marks. Several blocks naming one cell are its
  lines. A cell that comes before the one above it begins another table.
  Everything a paragraph can do, a cell can, with no code of its own.
* **`TextTables` finds tables** among the blocks and repairs them
  (`normalize`): numbered from zero, no cell missing, one width a column.
  The editor repairs what it is given, so no operation has to leave a
  perfect grid behind it — removing lines can empty a cell or a row, and the
  repair puts that right.
* **A selection takes in cells whole** (`RichTextEditing.coveredBy`), as
  OneNote selects them: from one cell into another, the block of cells with
  those two at its corners; running into or out of a table, every cell it
  passes. Within a cell it takes in text. Deleting, formatting, copying and
  drawing the selection all go by what it takes in, and cells taken in are
  drawn filled, whole.
* **Cells are never joined.** Deleting across cells empties them. Delete,
  Backspace and Cut take away the rows and columns a block of cells takes in
  whole — and the table, taken in whole — as they take away text; typing
  over the cells only empties them, for the text typed to go in the first.
  A selection running into or out of a table takes away the rows it covers
  whole, and the text either side joins as it would. Backspace and Delete at
  a cell's edge do nothing, and from the line below a table step into it;
  Backspace in an empty cell takes its column away if that is empty all the
  way down, else its row if that is empty all the way along — undoing the Tab
  or Enter that made them — and else steps back a cell. Pasting into a cell
  makes lines of the cell; a table pasted elsewhere stays a table. Cells
  copied are a table of just those cells; plain text has a table's cells
  separated by tabs, as spreadsheets paste them.
* **`TableEditing` makes tables as OneNote does:** Tab at the end of a
  paragraph with words in it starts one; Tab in a cell goes on to the next,
  adding a column from the first row's last cell and a row from the table's
  last; Enter at the end of a row adds a row, and in the first cell of an
  empty row turns that row into a paragraph, leaving the table. Enter in any
  other cell starts another line of it. Rows and columns are added and
  removed from a cell's right-click menu.
* **Columns fit their text** (`RenderTextTable`), as a web page lays out a
  table: as wide as their longest line, and an inch at least, where there is
  room, else narrowed toward their longest word, sharing what room there
  is. A column's line is
  dragged to set its width, which every cell of the column keeps, so no row
  removed takes it away; a double-click fits it again. A dragged column
  grows no wider than its box allows, as a picture does, and dragged widths
  too wide for a box grown narrow give way together.

## Consequences

* Moving the caret up and down, and clicking, find cells by where they are
  on screen rather than by their order, since a table's cells lie side by
  side.
* A build that does not know tables shows their cells as paragraphs, in
  order, having lost nothing.
