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
page units; rotation is radians about the frame's centre.

| `type` | Payload |
| --- | --- |
| `text` | `blocks`: paragraphs with `kind`, `runs`, `indent`, `checked` |
| `ink` | `strokes`: `{tool, color, width, points}` |
| `image` | `assetId`, `fit`, `altText?`, `recognizedText?` |
| `pdf` | `assetId`, `pageIndex`, `extractedText?` |
| `math` | `source`, `mode` (`linear` \| `latex`), `displayStyle` |
| `table` | `columnWidths`, `rows` (row-major cells of blocks), `headerRow` |
| `group` | `childIds`, `label?` |

`points` is a flat array of `[x, y, pressure, tilt]` tuples, rounded to two
decimals. Flat rather than nested because a handwritten page holds hundreds of
thousands of samples, and this is both smaller on disk and loadable straight
into a `Float32List`.

Colours are 32-bit ARGB integers.

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

Titles, position among siblings, the search index, tags and embeddings live in
SQLite, because they are properties of how a page sits in a workspace rather
than of its contents. Attachments live in the content-addressed asset store;
the page refers to them by `assetId`.
