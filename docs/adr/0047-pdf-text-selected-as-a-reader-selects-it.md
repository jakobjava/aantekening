# 47. PDF text selected as a reader selects it

**Status:** accepted

## Context

A PDF page on a page of notes was a picture of itself. Its text could be
searched, since the search index reads it, but not selected or copied. Its
links, to the web or to another page of the same PDF, did nothing. A
reader such as Firefox lets you drag across a PDF's text to select it, and
click a link to follow it.

The same presses already meant something on the page. A click on a
worksheet set as the background places the caret, to type an answer there.
A press on a PDF page of its own picks it up, and a drag moves it.

## Decision

**The canvas lets the app select text it does not lay out itself**
(`CanvasText`). With the type-and-select tool, a press on such text, beneath
nothing else that a press would pick up, is held until it moves:

* **dragged, it selects** the text from where it was pressed to where the
  pointer is, as a reader does, and the pointer shows a text cursor over it;
* **let go of where it was pressed, it does what it did before**: on a
  worksheet, places the caret; on a PDF page of its own, picks the page up.
  A **double-click** selects a word;
* **with Ctrl held, a click opens a link**, and the pointer shows a hand
  over one. A plain click on a link keeps its old meaning, so typing over a
  link on a worksheet does not open a browser.

A finger dragged across the text scrolls, as across anything else. A PDF
page of its own is moved by dragging it where it has no text, or by its
handles. A text box or ink lying over the PDF's text takes the press, as it
did before.

**The text and links come from PDFium** (`PdfWordsCache`), read once for
each page of each PDF when the page is first shown, and kept. Each
character's box is kept in shares of the page, so the page shown at any
size and turned any way finds them. Lines are found from the boxes, in the
direction the text reads: across, or down a page turned on its side, or
upside down. A caret falls before the first character whose middle lies
past the pointer, on the line nearest it. What is picked is lit over the
page, and **Copy** and Ctrl+C copy it with its line breaks.

**A link to another page of the same PDF** brings that page into view, where
it lies on the page; a web address opens in the browser, as links in a text
box do.

## Consequences

* Selection keeps to one page of the PDF: a drag that leaves it selects to
  the nearest of its text.
* Text that PDFium cannot read (a scan, say) has no text to select; the
  page behaves as before.
