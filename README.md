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
  subpages, each joined to what it is in by a line. Click a line, or the
  chevron beside a name, to fold away what lies beneath; the panes remember
  what is folded. Right-click any of them (or long-press) to add to it, cut,
  copy, paste, rename or delete it. Deleting asks first; what is deleted stays
  in the workspace and can be restored.
* **Ribbon** — OneNote-style tabs (Home, Insert, Draw, Math, Review, View)
  across the top of the window, each in named sections. It stays put while
  you work; a tool's shortcut brings its tab forward, and any button can be
  dragged to another place, section or tab.
* **Tabs** — beneath the ribbon, as in a browser: open a page in a new tab
  from its menu, with a middle-click or with Ctrl+click, and have as many
  open as you like. Each tab has a sidebar of its own — its notebook, section
  and page, its open panel and its search — and the sidebar acts on the tab
  showing alone. Drag tabs to reorder them; the window remembers them, and
  going back to a tab finds its page where you left it.
* **Look** — one colour and its text, for focus: light and dark modes, each
  in a base and text colour of your choosing, and one accent colour or none.
  No icons, no rounded corners, no shadows; the interface is set in IBM Plex
  Sans or Mono, at any of five sizes. All in **Settings** (Ctrl+,), with the
  layout, the shortcuts, spelling and the AI's models.
* **Keyboard** — Ctrl+P goes to any page, section or notebook by a few
  letters of its name; Ctrl+Shift+P runs any command by name. Alt+arrows step
  through pages and sections and go back and forward; Alt+1–9 shows a tab;
  Ctrl+Shift+T reopens one. Every shortcut is listed, and can be changed, in
  the settings (F1).
* **Sidebar** — a strip of buttons down the left opens panels beside the page:
  the notebooks and pages, search, and a graph of the workspace.
  A panel's button closes it again, its columns are widened by dragging their
  edges, and the buttons can be dragged into another order, as the ribbon's
  can.
* **Pages** — each has its title and its date and time at the top, as in
  OneNote. The title is the page's name in the page list, so renaming either
  renames both; the date and time open pickers to change them. A page starts
  at its top-left corner and runs on to the right and down.
* **Infinite canvas** — scroll and zoom with a mouse wheel, a trackpad
  (two-finger scroll with momentum, pinch) or two fingers on a touchscreen; no
  separate pan tool. Scrollbars down the side and along the foot of the page,
  or **View → Page preview** for the whole page drawn small down its side, as
  code editors show a file: click or drag on it to go there. Undo and redo,
  with viewport culling so paint cost tracks what is visible.
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
* **Tables** — as in OneNote: type a word and press Tab, and it becomes the
  first cell of a table with the caret in the next. Tab in the last cell of
  the first row adds a column; Enter at the end of a row adds a row, and
  Enter in the empty row leaves the table; Backspace in an empty column or
  row takes it away again. Drag from one cell into another to select the
  cells between, and Delete takes them away as it does text: the rows and
  columns selected whole go, the rest are emptied. Columns fit their text, an
  inch wide at least while there is room; drag a column's line to size it,
  double-click the line to fit it again, and right-click a cell to add or
  remove rows and columns. Cells hold anything a paragraph can: formulas,
  lists, pictures.
* **Colours** — one palette for pens, text and highlights, plus a picker for
  any other colour.
* **Mathematics** — written inside the text box, in the flow of a sentence.
  Press Alt+= and type the formula right there, in a code face on a tinted
  box, with the formula typeset live just beneath; finish it and it is
  typeset in the line. Type in either syntax: LaTeX, or OneNote-style Simple
  syntax (`sum_(i=1)^n i^2`, `(a+b)/c`, `sqrt(x)`, `vec(1, 2, 3)`,
  `mat(1, 2; 3, 4)`, `cases(…)`), parsed by a real grammar. Formulas are
  stored as LaTeX either way, and switching syntax translates the formula.
  A formula takes the size and colour of the text it is written in. The
  **Math** tab has structures (fractions, roots, integrals, sums, brackets,
  bras and kets, accents, matrices) and symbols to click in, and a cheat
  sheet of the Simple syntax beside the page: click an example to write it.
* **Spelling** — words spelled wrongly are underlined with a wavy line as
  you type, in any number of languages at once; right-click one for
  corrections, to add it to your dictionary, or to ignore it. The **Review**
  tab turns it on and off and chooses among the languages installed;
  **Settings → Spelling** downloads British English, Dutch and German, adds
  any Hunspell dictionary (as LibreOffice uses) from its `.aff` and `.dic`
  files, and lists the words you have added.
* **Pictures and PDFs** — insert them onto the canvas to annotate, or into a
  text box as a printout, and resize them there by their corners. PDF pages
  are rendered sharply at any zoom and their text is searchable. Right-click
  one and **Set Picture As Background** to write over it: it goes beneath
  all ink and out of the way of clicks, until you right-click it to set it
  free again.
* **Right-click menus and copying** — right-click anything for the Home
  tab's text formatting, cut, copy, paste and paste text only, as in
  OneNote. Anything on a page copies and pastes — text, formulas, pictures,
  PDF pages, whole boxes, handwriting — with Ctrl+C, Ctrl+X and Ctrl+V too.
* **Search** — SQLite FTS5 across every page, ranked, with highlighted
  snippets. The best match opens as you type, with the words found marked on
  the page and the view on the first of them; Enter steps through the other
  pages that match.
* **Graph** — every notebook, section and page as a dot joined to what it is
  in, laid out by a force simulation, as Obsidian draws a vault. Drag the dots
  about; click one to open it.
* **AI** — every notebook, section and page has an AI of its own: press
  **Ctrl+J**, the **AI** button on the sidebar, or *Ask AI* in its menu.
  It opens on what you can make to learn from it, each from your notes and
  linked back to the very sentence each part comes from:
  * a **summary** set out as a study sheet — the gist, the ideas in
    numbered parts, the formulas in boxes, and what goes beyond your notes
    kept apart;
  * **flashcards** that turn over, graded by how well you knew them and
    shown again just before you would forget them (spaced repetition), each
    to correct or take out;
  * a **quiz** taken a question at a time, each answer explained, the ones
    you missed to take again;
  * the **key terms**, as a glossary.

  Or ask anything, as you would someone who has read every note you ever
  wrote: answers start from that page, section or notebook, search the rest
  of your notes when they need to, look at your handwriting over PDF
  printouts, and can search the web. A small number after each statement
  names the sentence it comes from — hover to read it, click to open the
  page with the sentence marked — your notes in blue, the web in green, and
  the model's own knowledge ruled grey. Everything the AI makes stays with
  the page it is about, apart from your notes. While it works you see each
  step and how long it takes — the notes gathered, how much the model is
  reading, its thinking as it thinks, how fast it writes. Use a model on
  your own computer (Ollama, LM Studio, llama.cpp — nothing leaves it) or a
  provider you choose (Anthropic, OpenAI, Gemini, OpenRouter, Mistral,
  Groq, DeepSeek, or any OpenAI-compatible server); nothing is sent
  anywhere until you ask.
* **Links** — copy a link to any notebook, section, page or paragraph from
  its menu; paste it into a text box and Ctrl+click it to go there.

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
needs, and can be moved anywhere. Every push to `master` also builds one on
GitHub: open the latest run under the repository's **Actions** tab and
download **aantekening-windows**.

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
structures and symbols for formulas and the cheat sheet on **Math** (shown
while a formula is open), spelling and its languages on **Review**, and zoom
and the page preview on **View**. Formatting with a text box selected (rather than being typed
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
| Tab / Shift+Tab | Indent / outdent; after a word, start a table; in a table, the next / previous cell |
| Enter (in a table) | At the end of a row, add a row; in an empty row, leave the table |
| Ctrl+P / Ctrl+Shift+P | Go to a page, section or notebook / run a command, by a few letters of its name |
| Alt+Up / Alt+Down | Previous / next page in the section (with Shift: section in the notebook) |
| Alt+Left / Alt+Right | Back / forward through the pages the tab has shown |
| Ctrl+N, F2 | New page, rename the page |
| Ctrl+T / Ctrl+W / Ctrl+Shift+T | Open a new tab / close the tab showing / reopen the tab closed last |
| Ctrl+Tab / Ctrl+Shift+Tab | Next / previous tab (also Ctrl+Page Down / Page Up); Alt+1–9 shows a tab |
| Ctrl+Shift+E / Ctrl+F / Ctrl+Shift+G | The notebooks / search / graph, with the keyboard in them; Ctrl+\ hides or shows the panel |
| Ctrl+J | The AI of the page, section or notebook showing, and back |
| Ctrl+, / F1 / Ctrl+Shift+D | Settings / every shortcut, to change / light or dark |
| Ctrl+click (on a link) | Follow it: to a note, or to the web |
| V or T, P, H, E | Type-and-select, pen, highlighter, eraser (outside a text box); shows the Home or Draw tab |
| Ctrl+F1 | Collapse or show the ribbon |
| Ctrl+A, arrow keys | Select everything; nudge the selection (Shift: further) |
| Shift+click | Add to or remove from the selection |
| Ctrl+scroll, Ctrl+= / Ctrl+− / Ctrl+0 | Zoom, or reset to 100% |
| Scroll, space+drag, middle-drag | Move around the page with any tool |
| Enter / Shift+Enter (in search) | Open the next / previous page found; Esc clears the search |
| Enter or Esc (in the title) | Back to the page |

The shortcuts of commands can be changed in **Settings → Keyboard**; those of
typing are fixed.

Arrowing into a typeset formula, or clicking it, shows its source again with
the caret in it; arrowing off either end goes back to the text beside it and
typesets it. In a formula, Tab moves to the next place a structure left to
fill in, Enter or Esc finishes it, and Ctrl+Shift+M switches between Simple
and LaTeX. Backspace after a formula selects it before deleting it.

Simple syntax, in short: `x^2`, `x_i`, `a/b`, `sqrt(x)`, `root(3, x)`,
`sum_(i=1)^n`, `prod`, `int_a^b`, `lim_(x->0)`, `vec(v)` (arrow) and
`vec(1, 2, 3)` (column), `mat(1, 2; 3, 4)` (also `bmat`, `vmat`, `matrix`),
`cases(x, x>0; -x, x<0)`, `abs(x)`, `norm(v)`, `set(1, 2)`, `binom(n, k)`,
`n!`, `f'(x)`, `ket(psi)`, `bra(phi)`, `braket(phi, psi)`,
`braket(phi, H, psi)`, Greek letters by name, `oo`, `->`, `<=`, `!=`, `+-`,
`*`, `"text"`. Any `\command`, or LaTeX in backticks, passes through as it
is. **Math → Cheat sheet** lists it all.

If scrolling or zooming with a trackpad ever jumps, run the app with
`AANTEKENING_TRACE_INPUT=1` to print every pointer event as the engine
delivers it, every key, and every change of view with the code that made it.

### Tests

```bash
dart analyze
(cd packages/aantekening_core  && dart test)
(cd packages/aantekening_store && dart test)
(cd packages/aantekening_ai    && dart test)
(cd packages/aantekening_spell && dart test)
(cd packages/aantekening_math  && flutter test)
(cd packages/aantekening_canvas && flutter test)
(cd app/aantekening            && flutter test)
```

### Optional: the AI

Open any page's AI (**Ctrl+J**) and **Choose a model**. To keep everything
on your computer, install [Ollama](https://ollama.com) and pull a model that
can use tools and see pictures, then add **Ollama** under *On this
computer*:

```bash
ollama pull qwen3-vl:4b-instruct
```

An *instruct* model answers straight away. A model that thinks first answers
better, but without a graphics card its thinking can take many minutes; turn
**Think before answering** off in the settings for the models that allow it,
and give a model more **Room** there if it runs out before it answers. A
model that thinks longer than **Think for at most** (three minutes unless
you change it) is stopped and answers from what it has worked out.

Or add a provider under *Online* with its API key, which is kept in your
system's keychain. For web search with providers other than Anthropic,
which searches itself, point the settings at a
[SearXNG](https://docs.searxng.org) you run, or a Brave Search API key.
Nothing is contacted until you ask something.

## Layout

```
packages/aantekening_core     model + page format   (pure Dart)
packages/aantekening_store    SQLite, search, assets
packages/aantekening_canvas   infinite canvas engine
packages/aantekening_math     Simple syntax ⇄ LaTeX, typesetting
packages/aantekening_ai       AI providers, citations, the note agent
packages/aantekening_spell    spell checking, Hunspell ported to Dart
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
`path_provider` (BSD-3). `aantekening_spell` is in large part a port of
[Hunspell](https://hunspell.github.io) 1.7.3 and those files are under
Hunspell's licence, MPL 1.1, GPL 2 or LGPL 2.1 — see its `LICENSE`. The
spelling dictionaries are not part of the app: they are downloaded from
[wooorm/dictionaries](https://github.com/wooorm/dictionaries) when a language
is first chosen, each under its own licence, which is saved beside it. The
note format is plain JSON in a plain SQLite file — both readable without this
application.
