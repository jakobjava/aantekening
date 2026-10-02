# 20. Reading other programs' notes as they were

**Status:** accepted; what is brought from OneNote added to by ADR 28

## Context

The person's notes are in OneNote and Xournal++, and should come over
without losing anything: every page where it was, every text box one text
box, its tables, pictures, files and handwriting where they were, OneNote's
equations as formulas here, and every notebook, section and page with its
name and date. The converter they had used — a Python script over two
libraries — flattened revisions it should have followed, read only the
first version of objects, lost the order of pages, and made equations
pictures typeset by TeX.

## Decision

**A package of readers, and drafts.** `aantekening_interchange` is pure Dart
and knows nothing of the store: an importer (`NotesImporter`) reads files
into a `NotesDraft` — notebooks, sections and pages, their documents
already in this app's format, their pictures and files waiting in a folder —
and `DraftStoring` stores a draft in one transaction, so an import is there
whole or not at all. Importers run in an isolate, saying how far they have
got, and can be stopped. Another program is another importer.

**OneNote, from the file format up.** Nothing is taken from another
program; everything is read as Microsoft documents it:

* the `.onepkg` is a cabinet, its folder LZX-compressed: `Cabinet` and
  `LzxDecoder` unpack it, checking every block's checksum;
* each `.one` is a revision store ([MS-ONESTORE]): the file node lists as far
  as the transaction log says they were committed, each object space's
  revisions from the one its current content role names back through those
  it depends on, object revisions over the objects they revise, and every
  reference resolved through the global identity table in force where it
  was made;
* the objects are OneNote's ([MS-ONE]): the table of contents orders the
  sections and groups; each page's metadata gives its title, its level —
  a page's subpages are the pages of a higher level after it — and when it
  was made, which becomes the date and time beneath its title here.

Then, on the page, in page units — half-inches are 48, HIMETRIC 96/2540:

* **An outline is one text box**, at its offset, as wide as OneNote wrapped
  it. Its paragraphs keep their typeface, size, colour, bold, italic,
  underline, strikethrough, raised and lowered text, highlight and links;
  their alignment, and OneNote's own spacing — lines as high as the typeface
  sets them, not as this app spaces what is typed (`BlockSpacing`), so
  handwriting over the text still falls on its lines — or exactly as far
  apart as OneNote set them, unless that is closer than the type is tall,
  as OneNote keeps some paragraphs and shows them as the typeface sets
  them; their bullets as written — ○, ▪, ➢ — numbers and to-do boxes;
  their depth.
* **Tables** become the text box's table, cell by cell, with column widths,
  shading and borders shown or not.
* **Equations** are Office math: each structure's object says what it is, so
  a fraction is never taken for a power. They become LaTeX formulas —
  editable, and typeset here — broken where OneNote breaks them.
* **Pictures** go where they were, at their size, a background picture as a
  background; **files** attached become files in a text box (`EmbedKind.file`),
  opened with the program that opens them; **handwriting** keeps its strokes,
  colours, widths, pressure and highlighters.

Where something cannot come over — a picture whose data the notebook lacks,
a section behind a password — the import says so, by name, and brings the
rest.

**Xournal++.** A document is a page here, its pages one beneath the other,
each over the PDF or picture it annotates as background; its strokes keep
their pressure, its text its typeface, its TeX formulas become formulas —
or stay the picture Xournal++ made of one that uses TeX's own layout
commands. A folder of documents is a notebook of sections.

**This app's own exports** are zips of the notes folder's files for what was
exported (`ArchiveExport`), read back exactly, pages keeping their
identity so links between them still lead there.

## Consequences

* The page format grew what OneNote has and it lacked: typefaces, raised and
  lowered text, alignment, spacing, written bullets, cell shading and
  borders, attached files. Pages without them read as before.
* A typeface that is not installed is drawn in one made to the same
  measure — Carlito for Calibri, Liberation for Arial and Times — so lines
  break where they broke in OneNote wherever such a face is installed.
  Carlito comes with the app, Calibri being OneNote's own: drawn in any
  other face, its lines stood taller, and a paragraph's text sank further
  below where it was with every line.
* A file printout is kept by OneNote as a picture of each page, each
  referring to the file printed and saying which page it shows (properties
  `0x35C1` and `0x1DF9`, found in its files, not in [MS-ONE]). Its pages
  come over as pages of that PDF, kept once: its pictures are rendered at
  96 dots an inch, and blurred as soon as they were zoomed into.
* A OneNote container never resized by hand is as wide as its text and
  wraps at the width it had (`autoWidth`, `widthLimit`); one resized keeps
  its width. Given their widest width, a word alone filled a box across
  the page.
* OneNote files in its online format are recognised and refused with a
  reason; exporting the notebook from OneNote on a computer gives a file
  that is read.
* The readers are tested on a MIT-licensed OneNote section and a table of
  contents from onenote.rs, on cabinets an encoder in the tests writes, and
  on the model directly; the person's own notebooks were read to check
  every page came over.
