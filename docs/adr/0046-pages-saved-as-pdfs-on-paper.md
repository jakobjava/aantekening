# 46. Pages saved as PDFs, on paper

**Status:** accepted

## Context

Notes are handed in, printed and read on other devices as PDFs. A page
shown as sheets (ADR 32) is already paper: each sheet is a page of a PDF.
A page shown as one paper without end is not. It has no pages, it may be
wider than any paper, and what is written on it lies anywhere, with empty
stretches between. Cut into A4 every 1123 units, it would be sliced through
lines of text, formulas and pictures, and there would be blank sheets where
nothing was written. Shrunk onto one sheet, it would be unreadable.

## Decision

**A notebook, section or page is saved as one PDF** (Save as PDF… in its
menu, the Files settings, and the command palette for the page open). Its
pages come in the order the panes list them, each on new paper. Its
sections and pages, subsections and subpages nested, become the PDF's
bookmarks. The title and date are printed at the top of each page, where
the page shows them.

**A page shown as sheets is printed a sheet to a page** (`PrintLayout.ofSheets`),
as large as its paper: a page whose writing made its sheets wider is made
smaller to fit the paper again. Each sheet is printed with its template.
What lies on it is what has its middle on it, whole, as the page shows it,
and ink is cut at its edges.

**A page without sheets is cut onto A4 where nothing is cut through**
(`PrintLayout.ofCanvas`). Letter is not offered: the notes are kept where
A4 is the paper there is. The page is first drawn without its paper, a
pixel to a unit, and each row of pixels is counted: how much is drawn on
it, and from where to where across (`ContentProfile`). The breaks are
chosen from that, not from the elements' frames, so a gap between two
lines of one text box, the space under a formula or between two drawings
counts as a gap, while a text box's empty frame does not count as writing.
Then, sheet by sheet:

* **Each sheet is turned as what is on it needs.** Upright while it fits,
  on its side if that fits, and otherwise made smaller, turned whichever
  way makes it largest. A page with a wide table on it gets one landscape
  sheet, not a whole PDF of them.
* **It is cut at the lowest blank row** at least a quarter of the way down
  the sheet, a margin above its foot. A picture that does not fit what is
  left of a sheet goes whole onto the next. Only where there is no blank
  row (a drawing or picture taller than a sheet) is it cut, through the
  row with least drawn on it.
* **Empty stretches are left out.** The next sheet begins a margin above
  what follows the cut, however far down that is. The first begins at the
  page's own corner while the writing lies near it, so it sits on the
  paper as on the page.

**Or as one long page**, as large as the writing, up to the 200 inches a
PDF page may be (made smaller beyond that): to read on a screen, as it is
seen.

**The pages are drawn as pictures** (`PagePrinter`), at 150, 200 or 300
pixels to an inch, with the canvas's own painters and the page's own text
box laid out off the screen (as ADR 41's pictures for the AI are). The
pictures and PDF pages set as the background come first, then the rest by
how high each lies (pictures and PDF pages drawn themselves, text boxes and
TikZ pictures together), then the ink: the highlighter multiplied with
what it covers, the pen over it, inverting ink last. A sheet taller than
4096 pixels is drawn in strips, each a pixel longer than its share, so
that readers show no seam.

**The PDF is written by the app** (`PdfWriter`, in `aantekening_interchange`),
with no library added. A picture's rows are filtered as PNG filters them,
each the way that leaves least (Sub, Up or Paeth), and deflated: PDF reads
that as it is. Each sheet's pictures are made ready on an isolate while the
next sheet is drawn, and written as they come, so a long notebook is never
held whole. The file is written beside its name and put in place only once
it is whole. Stopped, or failed, it leaves nothing.

## Consequences

* The text of a PDF made this way cannot be selected or searched, and its
  printouts are pictures of them rather than their own pages. Keeping
  printouts as they were, and laying the typed text over the pictures
  unseen for search, would need a PDF's own objects copied and fonts
  embedded.
* A text box with a coloured background has no blank rows in it, so it is
  cut where least is drawn, which may be through a line.
* A sample notebook of a long page and three sheets at 150 pixels to an
  inch is 0.8 MB, and every page reads without warnings in Poppler and
  Ghostscript.
