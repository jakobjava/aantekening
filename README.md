# aantekening

A note-taking app for Linux, Windows and Android, in the spirit of OneNote:
an endless page to type, write and draw on anywhere, with real mathematics,
PDFs to annotate, and an AI that studies your notes with you.

Every note is a plain file in a folder you choose, so OneDrive, Dropbox or
Syncthing can keep it on all your computers. A local search index keeps
thousands of pages instant.

## Features

- **Pages that run on without end.** Type anywhere, and text boxes form
  around what you type. Draw with a pressure-sensitive pen or highlighter;
  hold the pen still and a stroke becomes the shape it was drawn as, or drag
  out shapes, axes and solids from the Draw tab. Move, resize and rotate
  anything.
- **Rich text.** Headings, lists, to-dos, tables, code, fonts, colours —
  one of them the inverse of whatever is beneath — and Markdown shortcuts,
  with spell checking in several languages at once.
- **Mathematics in the line.** Type a formula in LaTeX or a simple syntax
  (`sum_(i=1)^n i^2`, `mat(1, 2; 3, 4)`) and it is typeset as you write.
- **PDFs and pictures.** Insert them to annotate. PDFs stay sharp at any
  zoom and their text is searchable.
- **Organised like a notebook.** Notebooks, nested sections, pages and
  subpages, with tabs, a ribbon, a bin with undo, and a graph of it all.
- **Fast to navigate.** Ranked full-text search with the matches marked on
  the page. Ctrl+P jumps anywhere; Ctrl+Shift+P runs any command.
- **An AI of your own.** Summaries, flashcards with spaced repetition,
  quizzes and answers from your notes, each linked to the sentence it came
  from. It runs on your computer (Ollama, LM Studio) or with a provider you
  choose, and nothing is sent until you ask.
- **Safe with your notes.** Files are written whole or not at all. A clash
  between two computers keeps both versions. Daily backups can be restored.
- **Import.** OneNote notebooks (`.onepkg`, `.one`) and Xournal++ documents
  (`.xopp`), with their layout, formatting, handwriting and equations.
- **Calm to look at.** Light and dark, one accent colour, and no animations:
  everything appears at once.

For how to use it, including shortcuts, formula syntax and setting up the AI,
see [docs/using.md](docs/using.md).

## Getting it

Every push to `master` builds a Windows copy: open the latest run under the
repository's **Actions** tab and download **aantekening-windows**.

To build it yourself, install the [Flutter SDK](https://docs.flutter.dev/get-started)
(3.47 or newer). The first build downloads SQLite and PDFium, so it needs an
internet connection.

```bash
git clone https://github.com/jakobjava/aantekening.git
cd aantekening
flutter pub get
cd app/aantekening           # the app has to be run from here
flutter run -d linux         # or -d windows, or an Android device
```

Add `--release` for full speed. `flutter build windows --release` makes a
copy to keep in `build\windows\x64\runner\Release`.

On Windows you also need [Visual Studio](https://visualstudio.microsoft.com/downloads/)
2022 or newer with the **Desktop development with C++** workload, and
**Developer Mode** turned on (Settings → System → For developers).
`flutter doctor` says if anything is missing.

## Development

```
packages/aantekening_core          the model and page format (pure Dart)
packages/aantekening_store         the notes folder, SQLite index, search, backups
packages/aantekening_interchange   importing from OneNote and Xournal++
packages/aantekening_canvas        the canvas engine
packages/aantekening_math          Simple syntax ⇄ LaTeX, typesetting
packages/aantekening_ai            AI providers, citations, the note agent
packages/aantekening_spell         spell checking, Hunspell ported to Dart
app/aantekening                    the app
docs/                              architecture, file format, decisions, roadmap
```

Start with [docs/architecture.md](docs/architecture.md) and
[docs/file-format.md](docs/file-format.md). The reasons behind the main
choices are in [docs/adr/](docs/adr/), and what is not built yet is in
[docs/roadmap.md](docs/roadmap.md).

To check everything:

```bash
dart analyze
for p in core store interchange ai spell; do (cd packages/aantekening_$p && dart test); done
for d in packages/aantekening_math packages/aantekening_canvas app/aantekening; do (cd $d && flutter test); done
```

## Licences

Built on Flutter and Dart (BSD-3), SQLite (public domain), `sqlite3.dart`,
Riverpod, `pdfrx`, `archive` and `xml` (MIT), `flutter_math_fork`
(MIT/Apache-2.0), PDFium (BSD-3/Apache-2.0), and `file_selector`, `http`,
`path`, `crypto`, `path_provider` and `url_launcher` (BSD-3).

`aantekening_spell` is largely a port of [Hunspell](https://hunspell.github.io)
1.7.3, and those files are under Hunspell's licence (MPL 1.1, GPL 2 or
LGPL 2.1; see its `LICENSE`). Spelling dictionaries are not part of the app.
They are downloaded from [wooorm/dictionaries](https://github.com/wooorm/dictionaries)
when a language is first chosen, each with its own licence saved beside it.
