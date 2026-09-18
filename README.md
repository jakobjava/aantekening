# aantekening

A note-taking application for Linux, Windows and Android, built with Flutter.

An infinite canvas with moveable text boxes, pen and drawing support, imported
images and PDFs to annotate, and first-class mathematics — with everything held
in a local SQLite workspace so that navigating and searching thousands of pages
stays instant.

> **Status: groundwork.** The architecture, the page format, the storage and
> search layer, the canvas engine, the maths engine and a working application
> shell are in place and tested. See [`docs/roadmap.md`](docs/roadmap.md) for
> what is deliberately not built yet.

## What works today

* **Organisation** — notebooks, sections nested to any depth, pages and
  subpages. Soft deletion with restore.
* **Infinite canvas** — pan, zoom, marquee selection, moving elements, undo and
  redo, with viewport culling so paint cost tracks what is visible.
* **Ink** — pressure-sensitive pen, highlighter, stroke eraser; stylus barrel
  button erases.
* **Text boxes** — headings, bullets, numbering, to-dos, quotes, code, inline
  bold/italic/underline/strike/colour/highlight.
* **Mathematics** — two authoring modes. LaTeX, or OneNote-style linear input
  (`sum_(i=1)^n i^2`, `(a+b)/c`, `sqrt(x)`) parsed by a real grammar and
  typeset natively.
* **Search** — SQLite FTS5 across every page, ranked, with highlighted
  snippets, updating as you type.
* **Local AI** — optional, off by default, and wired only to runtimes on your
  own machine.

## Running it

Requires the Flutter SDK (3.47+).

```bash
flutter pub get                 # resolves the whole workspace, from any member
cd app/aantekening
flutter run -d linux            # or: -d windows, or an Android device
```

`flutter run` has to be started from `app/aantekening`, where the app's
`lib/main.dart` and platform folders live; the repository root only holds the
workspace definition.

Point the workspace somewhere else with `AANTEKENING_HOME=/path/to/dir`.

### Tests

```bash
dart analyze
(cd packages/aantekening_core  && dart test)
(cd packages/aantekening_store && dart test)
(cd packages/aantekening_ai    && dart test)
(cd packages/aantekening_math  && flutter test)
(cd packages/aantekening_canvas && flutter test)
(cd app/aantekening            && flutter test)
```

### Optional: local AI

Install [Ollama](https://ollama.com) and pull a chat model and an embedding
model, then enable the features in the app's AI settings:

```bash
ollama pull llama3.2
ollama pull nomic-embed-text
```

Nothing leaves your machine, and nothing is contacted until you switch it on.

## Layout

```
packages/aantekening_core     model + page format   (pure Dart)
packages/aantekening_store    SQLite, search, assets
packages/aantekening_canvas   infinite canvas engine
packages/aantekening_math     linear maths input + LaTeX
packages/aantekening_ai       local model clients
app/aantekening               the application
docs/                         architecture, file format, decisions, roadmap
```

Read [`docs/architecture.md`](docs/architecture.md) first, then
[`docs/file-format.md`](docs/file-format.md). The reasoning behind the load-
bearing choices is in [`docs/adr/`](docs/adr/).

## Open source

Flutter and Dart (BSD-3), SQLite (public domain), `sqlite3.dart` (MIT),
Riverpod (MIT), `flutter_math_fork` (MIT/Apache-2.0), `http`, `path`, `crypto`
and `path_provider` (BSD-3). The note format is plain JSON in a plain SQLite
file — both readable without this application.
