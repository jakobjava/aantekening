# Architecture

## Shape of the system

`aantekening` is a pub workspace: one Flutter application over seven Dart
packages. Dependencies point in one direction only.

```
                 app/aantekening             Flutter app: shell, panes, editor
                         │
     ┌───────────┬───────┼────────┬──────────┬──────────┐
     ▼           │       ▼        ▼          ▼          ▼
 _canvas         │     _math     _ai      _spell   _interchange   feature
     │           ▼       │        │                     │          packages
     │        _store ◄───┼────────┼─────────────────────┘
     └───────────┴───┬───┴────────┘
                     ▼
                  _core                     pure Dart: model + page format
```

* **`aantekening_core`** — pure Dart, no Flutter. The page document, the element
  hierarchy, ink, rich text, the organisational tree, geometry and identifiers,
  links to notes, and pages taken apart for machines to read (`PageDigest`).
  It runs anywhere: in the UI, in the store, in a background isolate, in tests,
  and in any future command-line importer.
* **`aantekening_store`** — the notes folder (a file for each notebook,
  section and page, ADR 19) and the SQLite index beside it that keeps them
  in step both ways; full-text search, embeddings, the content-addressed
  asset store, the bin, backups, exports, and what the AI makes, in tables
  of its own.
* **`aantekening_interchange`** — pure Dart: reading notes kept by other
  programs into drafts the store keeps whole (ADR 20). OneNote's `.onepkg`
  cabinets (LZX), its revision store and object model, OfficeMath as LaTeX;
  Xournal++ documents; this app's own exports.
* **`aantekening_canvas`** — the infinite canvas, running right and down from
  a page's top-left corner: viewport, spatial index, ink capture and the
  painted layers; and the same page folded into sheets on a desk, as pages
  (ADR 32). Knows nothing about maths or PDFs.
* **`aantekening_math`** — linear-input parsing and LaTeX rendering.
* **`aantekening_ai`** — pure Dart: models from any provider behind one
  interface, the conversation they share, citations, and the agent that
  answers from the notes (ADR 17). It reads the workspace only through a
  `NoteReader` the app gives it.
* **`aantekening_spell`** — pure Dart: Hunspell's checking and suggesting,
  ported, and a checker that runs it in an isolate of its own (ADR 12). It
  depends on nothing else here.
* **`app/aantekening`** — the window, navigation, and the wiring between them:
  `look/` the visual language (two colours and an accent, the theme, the
  drawn marks and the controls every part shares, ADR 18), `commands/` every
  command with a shortcut, the palette that finds them and the keys that run
  them, and `settings/` the settings window.

The reason for the split is not tidiness. `_core` having no Flutter dependency
is what lets the model be tested exhaustively and moved onto an isolate. The
canvas not depending on `_math` or a PDF engine is what lets it stay a
general-purpose surface while the app decides what an element looks like.

## Data flow for one keystroke

1. The editor mutates its `CanvasController`, producing a **new**
   `PageDocument` — documents are immutable, so an edit is a reference swap.
2. The controller rebuilds its spatial index and tells what shows the page
   its contents changed; moving the view it reports apart (ADR 21).
3. Only the affected painted layer repaints; the element widgets are untouched.
4. A debounced timer fires ~700 ms later and calls `PageRepository.saveDocument`.
5. That one transaction writes the body, the page row, the FTS entry and the
   asset links — and, by trigger, puts the page in the notes folder's
   outbox. The index can never describe a page that is not on disk.
6. Once the page has been still a moment, `FolderMirror.flush` writes the
   page's file to the notes folder, whole or not at all, and takes it out of
   the outbox. A crash between 5 and 6 leaves it in the outbox, and it is
   written the next time the app starts.

## Data flow for a question to the AI

1. The AI view hands the question to its `AiSession`, one per notebook,
   section or page, which lives on while other tabs show.
2. The `NoteAgent` asks the app's `NoteReader` for the scope: its pages,
   taken apart into citable passages and visuals (`PageDigest`), chosen to
   fit a share of the model's context (`NoteContext`), with handwriting over
   printouts drawn as pictures.
3. The provider's adapter turns the conversation into its API's terms —
   search results for Claude, numbered text for the rest — and streams the
   answer back as neutral events: text, cited spans, activity, tool calls.
4. Tool calls — search the notes, read a page, look at a visual, search the
   web — are run and answered, until the model is done.
5. The turn, and anything kept, is written to the AI's own tables; nothing is
   written to a page.

## Where speed comes from

Speed here is structural rather than the result of micro-optimisation:

| Concern | Decision |
| --- | --- |
| Opening a notebook | Page metadata and page bodies are separate tables, so listing never touches multi-megabyte blobs. |
| Painting a large page | A uniform-grid `SpatialIndex` makes paint cost track what is visible, not how much the page holds. |
| Scrolling and zooming | The page's layers are laid out in page units and shown through one transform; moving the view changes the transform, building and painting nothing (ADR 21). |
| Drawing handwriting | A pressure-varying stroke is one filled outline, recorded once per element. Ink is kept as tiles of pixels, drawn again only when the ink on them or the zoom changes, so a frame of a scroll draws a picture per tile rather than every stroke; the page moves by whole device pixels, so the tiles look as the strokes do (ADR 30). |
| A page shown as pages | The same layers seen through a fold: elements are placed a sheet's gaps further down, ink drawn sheet by sheet, and a template's lines worked out once for a size of sheet and drawn in one call per sheet in view; it costs what one paper does (ADR 32). |
| Every frame | The canvas is a repaint boundary, so the page built again as the view moves on repaints nothing around it; a screen reader is told where the page's parts are once the view rests. |
| PDF pages | Drawn from pictures shared by every view of them, never blank once drawn: a new zoom sharpens the page from the nearest picture there is; a page is drawn whole at most 2048 pixels wide, and in tiles about the view beyond. |
| Ink latency | The stroke in progress lives in its own layer; a new sample repaints only that. |
| Handwriting volume | Samples are one flat `Float32List`; consecutive strokes join one element. |
| Search | FTS5 with `bm25` ranking, keyed by `pages.rowid` so re-indexing is a primary-key delete plus insert. |
| Reordering | Sibling order is a `REAL` fractional index, so a drag writes one row. |
| Repeat queries | Prepared statements are cached on the connection. |
| Saving handwriting | Each element's JSON is kept with it, so a save writes out only what changed, and handwriting's numbers are written without a general encoder; pages are gzipped at a level four times as fast as the default. |
| Opening and saving a long page | Past 128 KiB, a page is decompressed and parsed, compressed and written to the notes folder on an isolate of its own, so the window never waits on it. |
| An idle laptop | Nothing wakes the app while nothing happens: the notes folder is written when something is queued, not polled, and the caret stops blinking after ten seconds. |
| Save latency | WAL journalling, so reads proceed while a save is in flight. |

## Concurrency

Every repository method is `async` even though `sqlite3` is synchronous. The API
is shaped now for the isolate-backed connection it will get later, so that move
will not be a breaking change. See `docs/roadmap.md`. Meanwhile the work on a
long page that needs no database — parsing it, compressing it — already runs on
an isolate of its own (`away`), and saves are queued so that one finishing
early never lands after a later one.

## Platforms

Linux, Windows and Android share all Dart code. The only platform-specific
pieces are the notes folder and the index beside the app, the directory for the preferences
and spelling dictionaries (`path_provider`), and the SQLite and
PDFium libraries, which `package:sqlite3` and `pdfrx` fetch prebuilt for each
platform as the app is built — SQLite with FTS5. Nothing in the codebase
branches on platform, except the trackpad scaling Linux needs (see
`trackpadPanScale`), the aiming of scrolling and trackpad gestures at the
pointer that GTK's reporting needs (see `TrackpadAim`, applied by the app's
binding before an event is routed) and the Linux window's title bar.

## Testing

Each package carries its own suite; there is no mocking of SQLite — the store
tests run against a real in-memory database, including FTS5. The maths package
additionally parses every expression it generates with the actual TeX renderer,
so a translation that merely looks plausible cannot pass; the app does the same
for every structure and symbol on the Math tab and every example on the cheat
sheet. The spell checker was held to libhunspell's own verdicts on a large word
list in each language, and its tests keep small dictionaries whose verdicts are
Hunspell's.
