# 52. PDFs that carry their text

**Status:** accepted; revises ADR 46

## Context

The notes are handed to AIs to read: a chat they are uploaded to, an
agent given the file. The PDF of ADR 46 is pictures, so an AI reads every
page off its pixels. It reads typed formulas back from their glyphs,
where the app has their LaTeX, and gets subscripts and signs wrong. It
finds no word of a page searched for, and a person can select nothing in
it either.

Most of what is written is written onto printouts. Of the 161 pages of
the person's school notes, 60 have text boxes typed onto PDF pages, 775
of them: answers in the blanks of worksheets, values in the cells of a
table of measurements, labels in drawings. Each means something only
with the sheet's own text around it. The in-app AI reads a printout's
text whole and what was typed onto it after it, so it ties answers to
the wrong blanks (ADR 44). Most printouts are scans whose text was read
by machine, and their text holds its lines out of order: "Name:", then
the title, then "Klasse:" two lines later.

236 of the 248 PDF pages have a text layer, and none is turned. PDFium
gives each of their characters with its box (ADR 47). The page's own
text box lays every line out, formulas and all, off the screen (ADR 41).

A folder for AIs was tried first: a Markdown file to each page, the
pictures beside it. It reads well, but the PDF already shows all of a
page, its layout, colours and handwriting. What it lacks is the text. A
second export would only say the same thing again, in a form people
cannot read.

## Decision

**The pages stay pictures, and their text is laid over them, unseen**,
as a scan read by machine keeps its text. Each line is put where its
picture shows it, stretched across the line, so a reader selects it where
it is seen, searches it, copies it, and gives it to an AI as text.
`PdfWriter.addPage` takes the lines (`PdfText`). It writes them in render
mode 3, which paints nothing, in a font of no glyphs the app writes
itself (`GlyphlessFont`, 620 bytes, as Tesseract's): a composite font
whose codes are the characters, all mapped to its one glyph by its
CIDToGIDMap and back to themselves by its ToUnicode map. So any character
is written, characters past the first 65,536 by codes of their own. A
line is as high as its box, or lower where that would squeeze its
characters narrower than they are, since readers then take a formula's
spaces for none. Each line is followed by a space, so the next is read
apart from it.

**A page's text is what the page shows, in the order it is read**
(`printedText`):

* **the title, the day and time it was written**, as printed at its top,
  and above them, in the margin, **the notebook, sections and pages it is
  in** (`Physik › Sonnensystem`), which the paper does not print;
* **typed text a line at a time, where the page's text box laid it out**
  (`layOutLines`, sharing `drawTextBoxes`'s tree): a list's mark with its
  line, and a formula as its LaTeX between dollar signs. `BlockParagraph`
  carries its `BlockView`, so each laid-out line is mapped back to the
  runs it was written in;
* **a printout's own text, line by line as it stands**: its words read
  by PDFium (`PagePrinter.wordsOf`) and put in reading order by
  `SheetReading`, whatever order the PDF holds them in;
* **what was typed onto a printout, where it was typed, between ⟦ and
  ⟧**: in the line it stands on, where it begins (`Name: ⟦Max⟧`, a pH
  value under its volume), or under the line, or between the lines. A box
  of one line is placed by the whole box, since a formula stands taller
  than its line. A line in the top quarter of a tall box is above its
  text, as a label is above the formula typed under it. A blank it
  covers, and the rule lines after an answer typed under a task, are left
  out of the order. A reader that reads a PDF's text as it is written gets
  the worksheet as it was filled in, and one that reads it by where it
  lies finds each answer in its blank;
* the text read out of a picture, and a TikZ picture's source, over it.

Handwriting has no text: only the picture shows it. The pages go in the
order the panes list them, as before. What a page's paper shows of it
carries its text: on a page shown as sheets, what has its middle on it;
on one cut onto A4, each line whose middle is on that sheet. The title
and where the page is go on its first.

**The files on the pages are attached to the PDF** (Attach the files on
the pages, on unless turned off). The PDFs, pictures and files are kept
as they were brought in, each once, by the name it came with ("Foto
2.png" for a second "Foto.png"). They are whole and sharp, with every
page of a PDF, also pages placed on no page. The PDF holds all the notes
hold.

## Consequences

* The PDF of the person's notes, 161 pages on 545 sheets, reads in
  Poppler as the notes do. The physics scripts' formulas stand in their
  sentences as LaTeX: `Dabei bezeichnet G = ⟦$$6{,}67\cdot{10}^{-11}…$$⟧
  die Gravitationskonstante.` The chemistry worksheets read as they were
  filled in, the measured pH values in their row under the volumes. 190
  files are attached. Ghostscript draws every page without a warning, and
  `pdfdetach` lists and saves every file.
* It takes 152 seconds and is 375 MB, a third of it the files attached.
  Turned off, or with Small pictures, it is far smaller.
* Two columns side by side read across, line by line, both together.
  Labels typed into a drawing stand between the lines near them. The
  picture shows what each is.
* A typed box rotated on the page carries its text across the box round
  it, not along its turn.
* The in-app AI still reads a printout and what was typed onto it apart
  (ADR 44). `SheetReading` is in core so its digest can use it too, once
  it is given the words of each printout.
* Drawn and laid out off the screen, a table holding a formula trips a
  debug-only assertion in the formula's layout (`flutter_math_fork`'s
  `LayoutBuilder` asked for its intrinsic width), and the table is then
  not painted in a debug build. It did so before; a release build is not
  asked.
