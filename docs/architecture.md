# Architecture

## Shape of the system

`aantekening` is a pub workspace: one Flutter application over six Dart
packages. Dependencies point in one direction only.

```
                 app/aantekening             Flutter app: shell, panes, editor
                         │
     ┌───────────┬───────┼────────┬──────────┐
     ▼           ▼       ▼        ▼          ▼
 _canvas     _store    _math     _ai      _spell   feature packages
     │           │       │        │
     └───────────┴───┬───┴────────┘
                     ▼
                  _core                     pure Dart: model + page format
```

* **`aantekening_core`** — pure Dart, no Flutter. The page document, the element
  hierarchy, ink, rich text, the organisational tree, geometry and identifiers.
  It runs anywhere: in the UI, in the store, in a background isolate, in tests,
  and in any future command-line importer.
* **`aantekening_store`** — SQLite, full-text search, embeddings and the
  content-addressed asset store.
* **`aantekening_canvas`** — the infinite canvas, running right and down from
  a page's top-left corner: viewport, spatial index, ink capture and the
  painted layers. Knows nothing about maths or PDFs.
* **`aantekening_math`** — linear-input parsing and LaTeX rendering.
* **`aantekening_ai`** — interfaces to language models running locally.
* **`aantekening_spell`** — pure Dart: Hunspell's checking and suggesting,
  ported, and a checker that runs it in an isolate of its own (ADR 12). It
  depends on nothing else here.
* **`app/aantekening`** — the window, navigation, and the wiring between them.

The reason for the split is not tidiness. `_core` having no Flutter dependency
is what lets the model be tested exhaustively and moved onto an isolate. The
canvas not depending on `_math` or a PDF engine is what lets it stay a
general-purpose surface while the app decides what an element looks like.

## Data flow for one keystroke

1. The editor mutates its `CanvasController`, producing a **new**
   `PageDocument` — documents are immutable, so an edit is a reference swap.
2. The controller rebuilds its spatial index and notifies listeners.
3. Only the affected painted layer repaints; the element widgets are untouched.
4. A debounced timer fires ~700 ms later and calls `PageRepository.saveDocument`.
5. That one transaction writes the body, the page row, the FTS entry and the
   asset links. The index can never describe a page that is not on disk.

## Where speed comes from

Speed here is structural rather than the result of micro-optimisation:

| Concern | Decision |
| --- | --- |
| Opening a notebook | Page metadata and page bodies are separate tables, so listing never touches multi-megabyte blobs. |
| Painting a large page | A uniform-grid `SpatialIndex` makes paint cost track what is visible, not how much the page holds. |
| Ink latency | The stroke in progress lives in its own layer; a new sample repaints only that. |
| Handwriting volume | Samples are one flat `Float32List`; consecutive strokes join one element. |
| Search | FTS5 with `bm25` ranking, keyed by `pages.rowid` so re-indexing is a primary-key delete plus insert. |
| Reordering | Sibling order is a `REAL` fractional index, so a drag writes one row. |
| Repeat queries | Prepared statements are cached on the connection. |
| Save latency | WAL journalling, so reads proceed while a save is in flight. |

## Concurrency

Every repository method is `async` even though `sqlite3` is synchronous. The API
is shaped now for the isolate-backed connection it will get later, so that move
will not be a breaking change. See `docs/roadmap.md`.

## Platforms

Linux, Windows and Android share all Dart code. The only platform-specific
pieces are the workspace directory and the directory for the preferences
and spelling dictionaries (`path_provider`), and the SQLite and
PDFium libraries, which `package:sqlite3` and `pdfrx` fetch prebuilt for each
platform as the app is built — SQLite with FTS5. Nothing in the codebase
branches on platform, except the trackpad scaling Linux needs (see
`trackpadPanScale`) and the Linux window's title bar.

## Testing

Each package carries its own suite; there is no mocking of SQLite — the store
tests run against a real in-memory database, including FTS5. The maths package
additionally parses every expression it generates with the actual TeX renderer,
so a translation that merely looks plausible cannot pass; the app does the same
for every structure and symbol on the Math tab and every example on the cheat
sheet. The spell checker was held to libhunspell's own verdicts on a large word
list in each language, and its tests keep small dictionaries whose verdicts are
Hunspell's.
