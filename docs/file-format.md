# The page format

A page is a JSON document. It is the `document` of the page's file in the
notes folder (see [The notes folder](#the-notes-folder)), the `body` blob of
`page_bodies` in the index (gzipped above 4 KiB), and byte-identical to what
`Export page` writes to disk. There is no second, private representation.

```jsonc
{
  "formatVersion": 1,
  "id": "01J8ZC4T0E9WZ1Q5M2N3P4R5S6",   // ULID, matches pages.id
  "revision": 42,                        // increments on every edit
  "canvas": {
    "background": { "kind": "grid", "spacing": 24,
                    "lineColor": 520093696, "paperColor": 4294967295 },
    "paperWidth": 816                    // optional printable-width guide
  },
  "elements": [ /* … */ ]
}
```

## Elements

Every element carries `id`, `type`, `frame`, `createdAt`, `updatedAt`, and
optionally `z` and `locked`. `frame` is `{x, y, width, height, rotation?}` in
page units, from the page's top-left corner, so `x` and `y` are not negative;
rotation is radians clockwise about the frame's centre. Ink has no
rotation of its own: turning or scaling handwriting rewrites its samples, and
its frame is the box around its strokes. A text box's text starts 6 units in
from its frame's sides and 12 below its top, the band it is moved by, and
the frame reaches 8 below it.

`locked: true` makes an element part of the page's background — a picture or
PDF page set as the background to write over. It is drawn beneath all ink
and everything else, in `z` order among the other backgrounds, and cannot be
picked, moved or erased until it is taken out of the background again.

| `type` | Payload |
| --- | --- |
| `text` | `blocks`: see [Rich text](#rich-text) below |
| `ink` | `strokes`: `{tool, color, width, points}` |
| `image` | `assetId`, `fit`, `altText?`, `recognizedText?` |
| `pdf` | `assetId`, `pageIndex`, `extractedText?` |
| `math` | `source`, `mode` (`linear` \| `latex`), `displayStyle` |
| `table` | `columnWidths`, `rows` (row-major cells of blocks), `headerRow` |
| `group` | `childIds`, `label?` |

An image's `fit` is `contain`, `cover` or `stretch`; a picture stretched out
of its proportions by a side of its selection box becomes `stretch`, so it
fills the frame it was given.

`math` elements are what earlier builds made for a formula on its own. New
formulas are written inside text boxes; a `math` element is converted into a
text box the first time it is double-clicked.

A highlighter stroke's `width` is the height of its chisel nib, and its
translucency is in its `color`'s alpha.

`points` is a flat array of `[x, y, pressure, tilt]` tuples, rounded to two
decimals. Flat rather than nested because a handwritten page holds hundreds of
thousands of samples, and this is both smaller on disk and loadable straight
into a `Float32List`.

Colours are 32-bit ARGB integers.

## Rich text

A text box's `blocks` are its paragraphs, in order. A block is either text:

```jsonc
{
  "kind": "bulleted",     // paragraph (omitted), heading1-3, bulleted,
                          // numbered, todo, code, quote
  "indent": 1,            // nesting depth, omitted when 0
  "checked": true,        // to-dos only, omitted when false
  "bullet": "dash",       // bulleted lists only, omitted for the default disc
  "marker": "➢",          // a bullet as written elsewhere, drawn instead
  "align": "center",      // start (omitted), center or end
  "spacing": { "before": 4, "after": 0, "line": 14 }, // as written elsewhere
  "runs": [
    { "text": "area " },
    { "text": "\\pi r^2", "math": "latex" }, // a formula
    { "text": " exactly", "marks": { "bold": true } }
  ]
}
```

or an embedded object on a line of its own:

```jsonc
{ "embed": { "kind": "pdfPage", "assetId": "01J…", "page": 3,
             "width": 816, "height": 1056, "text": "…page text…" } }
```

**Formulas are runs.** A run with `math` set is a formula whose `text` is its
LaTeX. `math` is always `latex` in pages written now, however the formula was
typed: Simple syntax is only a way of editing, translated each way. Pages from
earlier builds may hold `linear` runs, whose `text` is Simple syntax; they are
translated to LaTeX when the page is opened, and saved that way. Keeping
formulas in the flow of the text is what lets one sit in the middle of a
sentence, and it means a build that does not know about formulas still shows
their source rather than losing them. Formulas are never
merged with neighbouring runs. A formula alone in its block is typeset in
display style.

`marks` holds only the formatting that is set: `bold`, `italic`,
`underline`, `strikethrough`, `code`, `color`, `highlight`, `link`, `size`
(in points; 11 is the body size), `font` (a typeface's family name, kept from
the program the text was written in and drawn in a typeface of the same
measure where it is not installed) and `script` (`superscript` or
`subscript`). A formula's marks carry only `color` and
`size`: it is typeset by its own rules, so bold or underline mean nothing to
it. A highlight on a formula, whole or in part, is in its LaTeX, as
`\colorbox{#FFEF9D}{$…$}`, in the highlight's colour as it looks on the white
paper.

A bulleted block's `bullet` is the mark before its items: `disc`, the default,
which nests as a disc, then a circle, then a square, or `dash`, which stays a
dash at every level. Typing `* ` starts a list of discs and `- ` one of dashes,
as Word does. A `marker` is a bullet as another program wrote it — `○`,
`▪`, `➢` — drawn as its shape where the page draws one, and as the character
otherwise; `bullet` still says which list it is.

`spacing` lays a paragraph out as the program it came from did: `before` and
`after` are the space above and below it and `line` the height of its lines,
all in points; without `line`, lines are as high as the typeface sets them.
A block without `spacing` is laid out as the page lays out what is typed
on it. Imported text keeps it, so handwriting over the text still falls on
its lines.

**Tables** are runs of blocks, each with a `cell` naming the cell it is a
line of, in reading order, as Word keeps tables:

```jsonc
{ "runs": [{ "text": "Name" }], "cell": { "row": 0, "column": 0, "width": 96 } }
{ "runs": [{ "text": "Age" }],  "cell": { "row": 0, "column": 1 } }
```

Rows and columns count from zero. Several blocks in a row with the same cell
are its lines; a cell that comes before the one above it in reading order
begins another table. `width` is the column's width in page units, where its
line was dragged, carried by every cell of the column; without it the column
fits its text. A cell may carry `shading`, its background as an ARGB
colour, and `"borders": false` when its lines were hidden; the editor then
draws them faint, so the table can still be seen. A build that does not know tables shows the cells as
paragraphs, one after another. Readers repair a table missing cells by adding
them empty.

A text box with `"autoWidth": true` widens to fit its longest line, up to a
limit, as a new OneNote container does; resizing it by hand clears the flag.

**Embeds** are pictures (`"kind": "image"`), PDF pages (`"pdfPage"`, with
a zero-based `page`) and attached files (`"file"`, with the file's `name`)
from the asset store. A file is shown as its name, type and size, and
opened with whatever opens it on the computer. `width` and `height` are the
preferred size in page units, as the handles at its corners set them; a box
narrower than that shows the object scaled down to fit. `text` is indexed for search — a PDF page's text layer, or a
picture's description.

## Links to notes

A link to a note is a URI, and may be a text run's `link`:

* `aantekening://notebook/<id>` and `aantekening://section/<id>`
* `aantekening://page/<id>`, with a place on the page after `#`:
  `element=<id>`, and in a text box `&block=<n>` for its paragraph, counted
  from zero, and `&from=<i>&to=<j>` for words of it — a sentence an answer
  cites — as offsets into the paragraph's text, its runs' text joined.

Identifiers are the workspace's own, so a link keeps pointing at the same
thing however it is renamed or moved.

## What the AI makes

Nothing the AI writes is part of a page. What it makes is in tables of its
own, beside the notes and never in them:

* `ai_threads`: a conversation about a notebook, section or page, named by
  `scope_kind` and `scope_id`.
* `ai_turns`: each question, its answer as shown, and the turn as the model
  had it, to go on from. An answer is JSON: its Markdown, in which `⟦1,3⟧`
  after a stretch names the citations it draws on, counted from one; and
  its citations, each with the link or web address cited — to the sentence,
  for the notes — its title, whether it is from the notes or the web, and
  the words cited. Flashcards and quizzes in an answer are fenced blocks in
  the Markdown, marked `flashcards` and `quiz`, holding JSON lists.
* `ai_items`: what was kept about a scope. A study set — `kind` `summary`,
  `flashcards`, `quiz` or `terms` — holds JSON with `"study"` naming its
  kind: a summary's `title`, `gist`, `sections` of `points`, `formulas` and
  what goes `beyond` the notes; flashcards' `cards`; a quiz's `questions`;
  the key `terms`. Each card, question and point carries the citations it
  comes from, and each card and question an `id`. A kept answer (`kind`
  `answer`) holds the answer's JSON.
* `ai_reviews`: how each card of a set of flashcards is learnt — by
  `item_id` and `card_id`, its spaced-repetition state as JSON (when it is
  due, the gap and ease of its reviews, how often it was forgotten) and
  `due_at`. Kept apart from the set, so a card corrected or a set made
  again keeps what was learnt of the cards that stay.

## Compatibility rules

The format is designed to be read by builds that did not write it:

* **Unknown element types are skipped**, not treated as corruption. A page
  written by a newer build still opens, minus what this build cannot draw.
* **Unknown fields are ignored**, so additive changes need no version bump.
* **Missing or wrongly typed fields fall back to defaults** rather than
  throwing. Only a document that is not a JSON object is rejected outright.
* `formatVersion` rises only for a change a previous build could not safely
  ignore.

These rules exist because the alternative — refusing to open a file — locks
someone out of their own notes.

## What is *not* in the page document

Titles, the date shown beneath a title (`created_at`), position among
siblings and tags are properties of how a page sits among the notes rather
than of its contents: they are the page's file's `page` and `tags`, beside
its document. The search index and embeddings are the index's own, made
again from the files. Attachments live in the content-addressed asset store;
the page refers to them by `assetId`.

## The notes folder

The notes are a folder of files, one for each thing, so a service that
syncs folders can keep them on several computers (ADR 19):

```
aantekening.json          {"workspace": "<ULID>", …} — which notes these are
notebooks/<id>.json       sections/<id>.json
pages/<id>.json.gz        conversations/<id>.json   kept/<id>.json
assets/<ab>/<sha-256>     pictures, PDFs and files, by their contents
```

Every file is JSON — a page's gzipped — beginning with its `kind` and
`format`:

```jsonc
{ "kind": "page", "format": 1,
  "page": { "id": "01J…", "sectionId": "01J…", "title": "…", "createdAt": … },
  "tags": ["exam"],
  "assets": [ { "id": "01J…", "sha256": "…", "mimeType": "image/png", … } ],
  "document": { "formatVersion": 1, … } }   // the page document above
```

A notebook's file holds `notebook`, a section's `section`; a conversation's
and a kept item's hold its `row` and `children` as the index has them. A
page's `assets` name the files in `assets/` its document refers to by
`assetId`, so another computer can find them by their SHA-256.

A notebook, section or page in the bin has `deletedAt` set, and is
restored by clearing it. A thing deleted for good leaves a **tombstone** where its file was —
`{"kind": "page", "format": 1, "id": "01J…", "purgedAt": 1758…}` — so every
computer lets it go. A file that is missing deletes nothing. A file of a
`format` above this build's, or one that cannot be read, is left alone.

Files are written beside where they go (a name starting with `.`), flushed
and moved over it. A sync service's copy of a page's file — any name that is
not an identity — becomes a page of its own and is removed.

## Exports and backups

**An export** (`.aantekening`) is a zip of the files of what was exported,
laid out as in the notes folder, with `aantekening-export.json` naming the
notebooks, sections and pages in it at its root instead of
`aantekening.json`. Importing one gives the notes back, pages keeping their
identity.

**A backup** is a zip of the whole notes folder as it was, restored into a
folder of its own as notes of their own.
