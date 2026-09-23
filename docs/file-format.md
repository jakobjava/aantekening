# The page format

A page is a JSON document. It is stored as the `body` blob of `page_bodies`
(gzipped above 4 KiB) and is byte-identical to what `Export page` writes to
disk. There is no second, private representation.

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
its frame is the box around its strokes.

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
`underline`, `strikethrough`, `code`, `color`, `highlight`, `link`, and `size`
(in points; 11 is the body size). A formula's marks carry only `color` and
`size`: it is typeset by its own rules, so bold or underline mean nothing to
it. A highlight on a formula, whole or in part, is in its LaTeX, as
`\colorbox{#FFEF9D}{$…$}`, in the highlight's colour as it looks on the white
paper.

A bulleted block's `bullet` is the mark before its items: `disc`, the default,
which nests as a disc, then a circle, then a square, or `dash`, which stays a
dash at every level. Typing `* ` starts a list of discs and `- ` one of dashes,
as Word does.

A text box with `"autoWidth": true` widens to fit its longest line, up to a
limit, as a new OneNote container does; resizing it by hand clears the flag.

**Embeds** are pictures (`"kind": "image"`) and PDF pages (`"pdfPage"`, with
a zero-based `page`) from the asset store. `width` and `height` are the
preferred size in page units, as the handles at its corners set them; a box
narrower than that shows the object scaled down to fit. `text` is indexed for search — a PDF page's text layer, or a
picture's description.

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

## What is *not* in the page file

Titles, the date shown beneath a title (`pages.created_at`), position among
siblings, the search index, tags and embeddings live in SQLite, because they
are properties of how a page sits in a workspace rather than of its contents. Attachments live in the content-addressed asset store;
the page refers to them by `assetId`.
