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
  subpages. Right-click any of them (or long-press) to add to it, cut, copy,
  paste, rename or delete it. Deleting asks first; what is deleted stays in the
  workspace and can be restored.
* **Ribbon** — OneNote-style tabs (Home, Insert, Draw, Math, View) across the
  top of the window, each in named sections. It stays put while you work; a
  tool's shortcut brings its tab forward, and any button can be dragged to
  another place, section or tab.
* **Sidebar** — a strip of buttons down the left opens panels beside the page:
  the notebooks and pages, search, a graph of the workspace, and the local AI.
  A panel's button closes it again, its columns are widened by dragging their
  edges, and the buttons can be dragged into another order, as the ribbon's
  can.
* **Pages** — each has its title and its date and time at the top, as in
  OneNote. The title is the page's name in the page list, so renaming either
  renames both; the date and time open pickers to change them. A page starts
  at its top-left corner and runs on to the right and down.
* **Infinite canvas** — scroll and zoom with a mouse wheel, a trackpad
  (two-finger scroll with momentum, pinch) or two fingers on a touchscreen; no
  separate pan tool. Undo and redo, with viewport culling so paint cost tracks
  what is visible.
* **Selection** — one tool moves, resizes and rotates anything on the page —
  text boxes, pictures, PDF pages, handwriting — alone or as a group. A corner
  resizes in proportion; a side, dragged anywhere along it, stretches in that
  direction alone. Rotation snaps to upright, sideways and the diagonals. A
  marquee over handwriting picks out just the strokes inside it.
* **Ink** — pressure-sensitive pen and a OneNote-style chisel highlighter, each
  with its own colour and width; stroke eraser; stylus barrel button erases.
* **Text boxes** — OneNote-style: click anywhere and a caret appears; start
  typing and a box forms around the text, widening as you type. Headings,
  bullets, numbering, to-dos, quotes, code, font size, text colour, highlight
  colour, bold/italic/underline/strike, Markdown shortcuts, and pictures and
  PDF pages on lines of their own. Resizing a box changes its width, never its
  font.
* **Colours** — one palette for pens, text and highlights, plus a picker for
  any other colour.
* **Mathematics** — written inside the text box, in the flow of a sentence.
  Press Alt+= and type the formula right there, in a code face on a tinted
  box, with the formula typeset live just beneath; finish it and it is
  typeset in the line. Type in either syntax: LaTeX, or OneNote-style Simple
  syntax (`sum_(i=1)^n i^2`, `(a+b)/c`, `sqrt(x)`, `vec(1, 2, 3)`,
  `mat(1, 2; 3, 4)`, `cases(…)`), parsed by a real grammar. Formulas are
  stored as LaTeX either way, and switching syntax translates the formula.
  The **Math** tab has structures (fractions, roots, integrals, sums,
  brackets, accents, matrices) and symbols to click in.
* **Pictures and PDFs** — insert them onto the canvas to annotate, or into a
  text box as a printout. PDF pages are rendered sharply at any zoom and their
  text is searchable.
* **Search** — SQLite FTS5 across every page, ranked, with highlighted
  snippets. The best match opens as you type, with the words found marked on
  the page and the view on the first of them; Enter steps through the other
  pages that match.
* **Graph** — every notebook, section and page as a dot joined to what it is
  in, laid out by a force simulation, as Obsidian draws a vault. Drag the dots
  about; click one to open it.
* **Local AI** — optional, off by default, set up in its sidebar panel, and
  wired only to runtimes on your own machine.

## Running it

Requires the Flutter SDK (3.47+). The first build downloads SQLite and PDFium
for the platform, so it needs an internet connection.

```bash
flutter pub get                 # resolves the whole workspace, from any member
cd app/aantekening
flutter run -d linux            # or: -d windows, or an Android device
```

`flutter run` has to be started from `app/aantekening`, where the app's
`lib/main.dart` and platform folders live; the repository root only holds the
workspace definition.

Point the workspace somewhere else with `AANTEKENING_HOME=/path/to/dir`.

### On Windows

Install the [Flutter SDK](https://docs.flutter.dev/get-started/install/windows/desktop)
and Git, and [Visual Studio](https://visualstudio.microsoft.com/downloads/) 2022
or newer (Community is enough) with the **Desktop development with C++** workload.
Turn on **Developer Mode** (Settings → System → For developers), which
Flutter needs to link the app's plugins. `flutter doctor` says whether
anything is missing. Then, in PowerShell:

```powershell
git clone https://github.com/jakobjava/aantekening.git
cd aantekening
flutter pub get
cd app\aantekening
flutter run -d windows                  # add --release for full speed
```

`flutter build windows --release` makes a copy to keep: the folder
`build\windows\x64\runner\Release` holds `aantekening.exe` and what it
needs, and can be moved anywhere.

Notes are kept in `%APPDATA%\dev.aantekening\aantekening\workspace`;
`$env:AANTEKENING_HOME = 'D:\Notes'` before starting the app puts them
elsewhere.

### Using it

The default tool types and selects: click empty paper and start typing, click
a text box to place the caret, drag a box by the band along its top. Click a
picture, PDF page or ink to select it; drag across empty paper to select
several. Drag a corner to resize in proportion, a side to stretch that way,
and the knob above the box to rotate (hold Shift for 15° steps).

Notebooks, sections and pages are in the sidebar's first panel; right-click
one for what can be done to it. A new page opens with the caret in its title.

Commands are on the ribbon: text formatting on **Home**, pictures, PDFs and
formulas on **Insert**, the pens, their colours and widths on **Draw**,
structures and symbols for formulas on **Math** (shown while a formula is
open), and zoom on **View**. Formatting with a text box selected (rather than being typed
in) formats all of it. To rearrange the ribbon, drag a button to where you want
it; hold it over another tab's name to open that tab. **View → Reset ribbon**
puts everything back.

| Keys | Does |
| --- | --- |
| Alt+= or Ctrl+M | Start a formula at the caret; again (or Enter, Esc) to finish |
| Ctrl+Shift+M | Switch formulas between Simple and LaTeX syntax, translating the open one |
| Tab (in a formula) | Go to the next place a structure left to fill in |
| `$$` | Start a formula in LaTeX |
| Ctrl+B / I / U | Bold, italic, underline |
| Ctrl+− / Ctrl+E / Ctrl+Shift+H | Strikethrough, inline code, highlight |
| Ctrl+. / Ctrl+/ / Ctrl+1 | Bullets, numbering, to-do (Ctrl+Enter ticks it) |
| Ctrl+Alt+1–3, Ctrl+Shift+N | Headings, normal text |
| `- `, `1. `, `[] `, `# `, `> ` | Markdown shortcuts at the start of a line |
| Tab / Shift+Tab | Indent / outdent |
| V or T, P, H, E | Type-and-select, pen, highlighter, eraser (outside a text box); shows the Home or Draw tab |
| Ctrl+F1 | Collapse or show the ribbon |
| Ctrl+A, arrow keys | Select everything; nudge the selection (Shift: further) |
| Shift+click | Add to or remove from the selection |
| Ctrl+scroll, Ctrl+= / Ctrl+− / Ctrl+0 | Zoom, or reset to 100% |
| Scroll, space+drag, middle-drag | Move around the page with any tool |
| Enter / Shift+Enter (in search) | Open the next / previous page found; Esc clears the search |
| Enter or Esc (in the title) | Back to the page |

Arrowing into a typeset formula, or clicking it, shows its source again with
the caret in it; arrowing off either end goes back to the text beside it and
typesets it. In a formula, Tab moves to the next place a structure left to
fill in, Enter or Esc finishes it, and Ctrl+Shift+M switches between Simple
and LaTeX. Backspace after a formula selects it before deleting it.

Simple syntax, in short: `x^2`, `x_i`, `a/b`, `sqrt(x)`, `root(3, x)`,
`sum_(i=1)^n`, `prod`, `int_a^b`, `lim_(x->0)`, `vec(v)` (arrow) and
`vec(1, 2, 3)` (column), `mat(1, 2; 3, 4)` (also `bmat`, `vmat`, `matrix`),
`cases(x, x>0; -x, x<0)`, `abs(x)`, `norm(v)`, `set(1, 2)`, `binom(n, k)`,
`n!`, `f'(x)`, Greek letters by name, `oo`, `->`, `<=`, `!=`, `+-`, `*`,
`"text"`. Any `\command`, or LaTeX in backticks, passes through as it is.

If scrolling or zooming with a trackpad ever jumps, run the app with
`AANTEKENING_TRACE_INPUT=1` to print every pointer event as the engine
delivers it, every key, and every change of view with the code that made it.

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
model, then enable the features in the sidebar's **Local AI** panel:

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
packages/aantekening_math     Simple syntax ⇄ LaTeX, typesetting
packages/aantekening_ai       local model clients
app/aantekening               the application
docs/                         architecture, file format, decisions, roadmap
```

Read [`docs/architecture.md`](docs/architecture.md) first, then
[`docs/file-format.md`](docs/file-format.md). The reasoning behind the load-
bearing choices is in [`docs/adr/`](docs/adr/).

## Open source

Flutter and Dart (BSD-3), SQLite (public domain), `sqlite3.dart` (MIT),
Riverpod (MIT), `flutter_math_fork` (MIT/Apache-2.0), `pdfrx` (MIT) over
PDFium (BSD-3/Apache-2.0), `file_selector`, `http`, `path`, `crypto` and
`path_provider` (BSD-3). The note format is plain JSON in a plain SQLite
file — both readable without this application.
