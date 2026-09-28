# Using aantekening

## Finding your way

The default tool types and selects: click empty paper and start typing, click
a text box to place the caret, drag a box by the band along its top. Click a
picture, PDF page or ink to select it; drag across empty paper to select
several. Drag a corner to resize in proportion, a side to stretch that way,
and the knob above the box to rotate (hold Shift for 15° steps).

Notebooks, sections and pages are in the sidebar's first panel; right-click
one for what can be done to it. A new page opens with the caret in its title.

Commands are on the ribbon:

| Tab | Holds |
| --- | --- |
| **Home** | Text formatting |
| **Insert** | Pictures, PDFs, files and formulas |
| **Draw** | The pens, shapes, their colours and widths |
| **Math** | Structures, symbols and the cheat sheet, while a formula is open |
| **Review** | Spelling and its languages |
| **View** | Zoom, the page preview, resetting the ribbon |

Formatting a selected text box (rather than typing in it) formats all of it.
Drag a ribbon button to move it; hold it over another tab's name to open that
tab.

## Drawing and shapes

Hold the pen still for half a second at the end of a stroke, without
lifting it, and the stroke becomes the shape it was drawn as: a line, an
arrow, lines joined at corners, a triangle or other outline of straight
sides, a rectangle or square, an ellipse or circle. A stroke that is none of
these stays as it was written; a highlighter's is only ever straightened.
Keep the pen down and move it to reshape what it became: a line's far end
follows the pen, a corner of a rectangle or ellipse is pulled while the one
across from it stays, a corner of a triangle moves by itself. Lines settle
on level, upright and 45°, and a side nearly level is made so.

**Shapes** on the Draw tab (S) holds shapes to drag out on the page: lines
and arrows; outlines; graphs — axes, in one quadrant, four or in 3D, a
number line and a grid, ticked every square of the page's grid; and solids,
their hidden edges dashed. A click puts one down at its usual size. Shift
keeps a box square and a line to steps of 15°. Shapes are drawn in the
pen's colour and width, and are ink once drawn: picked, moved, resized,
turned and erased as handwriting is.

## Colours and fonts

**Inverted**, in the text colour's menu and first among the pen's colours,
is no colour of its own but the opposite of what is beneath: black on the
paper, white over a dark picture or highlight, so it can be read on
either. The **Font** menu on the Home tab sets text in the page's own
typeface, one the app brings — which looks the same on every computer — or
any installed on this one.

## Keyboard

Every shortcut is listed in the app under **F1**, where the shortcuts of
commands can be changed; those of typing are fixed.

| Keys | Does |
| --- | --- |
| Ctrl+P / Ctrl+Shift+P | Go to a page, section or notebook / run a command, by a few letters of its name |
| Alt+Up / Alt+Down | Previous / next page in the section (with Shift: section in the notebook) |
| Alt+Left / Alt+Right | Back / forward through the pages the tab has shown |
| Ctrl+N, F2 | New page, rename the page |
| Ctrl+T / Ctrl+W / Ctrl+Shift+T | New tab / close the tab / reopen the tab closed last |
| Ctrl+Tab, Alt+1–9 | Next tab, show a tab |
| Ctrl+Shift+E / Ctrl+F / Ctrl+Shift+G | Notebooks / search / graph; Ctrl+\ hides or shows the panel |
| Ctrl+J | The AI of what is showing, and back |
| Ctrl+, / Ctrl+Shift+D / Ctrl+F1 | Settings / light or dark / collapse the ribbon |
| V or T, P, H, S, E | Type-and-select, pen, highlighter, shapes, eraser |
| Ctrl+B / I / U | Bold, italic, underline |
| Ctrl+− / Ctrl+E / Ctrl+Shift+H | Strikethrough, inline code, highlight |
| Ctrl+. / Ctrl+/ / Ctrl+1 | Bullets, numbering, to-do (Ctrl+Enter ticks it) |
| Ctrl+Alt+1–3, Ctrl+Shift+N | Headings, normal text |
| `- `, `1. `, `[] `, `# `, `> ` | Markdown shortcuts at the start of a line |
| Tab / Shift+Tab | Indent / outdent; after a word, start a table; in a table, next / previous cell |
| Alt+= or Ctrl+M, `$$` | Start a formula (`$$`: in LaTeX) |
| Ctrl+Shift+M | Switch formulas between Simple and LaTeX |
| Ctrl+scroll, Ctrl+= / Ctrl+− / Ctrl+0 | Zoom, or reset to 100% |
| Scroll, space+drag, middle-drag | Move around the page with any tool |
| Ctrl+click on a link | Follow it, to a note or the web |

## Tables

Type a word and press Tab: it becomes the first cell of a table. Tab in the
last cell of the first row adds a column; Enter at the end of a row adds a
row, and Enter in the empty row leaves the table. Drag across cells to select
them; Delete takes away whole rows and columns selected and empties the rest.
Drag a column's line to size it, double-click it to fit the text again, and
right-click a cell to add or remove rows and columns.

## Formulas

Press Alt+= and type; the formula is typeset live beneath, and in the line
once finished (Enter or Esc). Arrowing into or clicking a formula shows its
source again. Tab moves to the next place a structure left to fill in. A
formula alone on its line is typeset large; end it with `#` to centre it.

Formulas are stored as LaTeX and can be typed in LaTeX or in the Simple
syntax, which **Math → Cheat sheet** lists in full:

`x^2`, `x_i`, `a/b`, `sqrt(x)`, `root(3, x)`, `sum_(i=1)^n`, `prod`,
`int_a^b`, `lim_(x->0)`, `vec(v)` and `vec(1, 2, 3)`, `mat(1, 2; 3, 4)` (also
`bmat`, `vmat`, `matrix`), `cases(x, x>0; -x, x<0)`, `abs(x)`, `norm(v)`,
`set(1, 2)`, `binom(n, k)`, `n!`, `f'(x)`, `ket(psi)`, `bra(phi)`,
`braket(phi, H, psi)`, Greek letters by name, `oo`, `->`, `<=`, `!=`, `+-`,
`*`, `"text"`. Any `\command`, or LaTeX in backticks, passes through as it is.

## The AI

Open any page's AI (**Ctrl+J**) and **Choose a model**. Nothing is sent
anywhere until you ask something.

To keep everything on your computer, install [Ollama](https://ollama.com),
pull a model that can use tools and see pictures, and add **Ollama** under
*On this computer*:

```bash
ollama pull qwen3-vl:4b-instruct
```

Without a graphics card, a model that thinks first can take minutes: turn
**Think before answering** off for it, or lower **Think for at most** (three
minutes by default). Give a model more **Room** if it runs out before it
answers; LM Studio and other servers that do not say how much they take need
it set.

Online providers keep their API key in the system's keychain. What each
answer and study set cost is shown with it, reckoned from the model's price
where the provider lists it (Requesty, OpenRouter, Anthropic); the model
chooser shows each model's price a million tokens read and written. **Notes per
question** sets how much of your notes goes with each question: 40k tokens by
default, and never more than a third of what the model can take. Web search
works by itself with Anthropic; with other providers, point the settings at a
[SearXNG](https://docs.searxng.org) you run, or a Brave Search API key.

## Where notes live

Every note is a file in the notes folder that **Settings → Files** chooses:
put it in OneDrive, Dropbox or Syncthing to have your notes on every computer.
Until one is chosen they are kept in the app's data folder (on Windows,
`%APPDATA%\dev.aantekening\aantekening\workspace`). Starting the app with
`AANTEKENING_HOME=/path/to/dir` uses another folder for that session.

## If scrolling misbehaves

Run the app with `AANTEKENING_TRACE_INPUT=1` to print every pointer event as
the engine delivers it, every key, and every change of view with the code
that made it.
