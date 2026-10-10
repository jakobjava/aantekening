# Using aantekening

## Finding your way

The window is the page, and a thin line of glass floating along its top —
or its foot, as **Settings → Layout** chooses: the **status line**. It shows
the mode the keys are in, as a dot of its colour, the tabs, the one showing
underlined in the accent, and the pen in hand,
a save under way and the zoom. Nothing else is shown until it is asked for.

**Space** — Ctrl+Space while typing, or a right-click — opens the **menu**
in the middle of the window, always in the same place: everything that can be done, each a key or two
away, on keys drawn as caps that a click presses as well. It opens further
layers: **Space f** formats text, **Space d** draws, **Space m** puts in
formulas, **Space s** works on the sheets, **Space i** inserts, **Space z**
is the view and **Space w** splits the window. Backspace goes back a layer
and Esc closes it. Formatting a selected text box, rather than typing in it,
formats all of it, and the marks stay on offer for the next: **Space f b
i** is bold and italic. A right-click in a text box offers what is to be
done there — a word spelled wrongly, a table, a link — and the text's and
the formulas' layers after it.

### Modes

As in vim, what a key does depends on the mode:

| Mode | Entered by | Its keys |
| --- | --- | --- |
| **Normal** | Esc | h j k l, or the arrows, go from thing to thing on the page, keeping to a line or a column; f puts a label on everything in view, to jump to by typing it; i or Enter types in the box picked, or a new one; o in a new box below; `$` a formula; x deletes, y copies, p pastes, u undoes, U redoes; m moves what is picked (h j k l or the arrows a step, H J K L ten); gg the top, G the foot; J K the next and previous page; H L back and forward; / search; : commands; Esc lets go of what is picked and what is searched for |
| **Insert** | i, or a click in text | Typing, as anywhere; Esc goes back to normal |
| **Draw** | d | p pen, h highlighter, e eraser, s shapes, l lasso; 1–9 the palette's colours; [ and ] thinner and thicker; c any colour |
| **Select** | v | The lasso; h j k l (or the arrows), and f, pick what is that way, or labelled, as well; d deletes, y copies, c cuts, m moves, a picks everything |
| **AI** | a, or Ctrl+J | o the overview; 1–9 a set to study; i the question; n a new conversation; c a conversation or an answer kept, by name; q a question ready to ask; h j k l (or the arrows) go to anything in it, ringed, Enter or Space pressing it; Esc lets go of it, and then goes back to the notes |

**?** shows the keys of the mode the page is in. A pause in the middle of
keys — after g, say — shows what can follow; typed on, nothing is shown.

### On the page

The default tool types and selects: click empty paper and start typing, click
a text box to place the caret. A text box shows nothing of itself until it is
clicked; then it is framed as a picture is, with handles on its sides to make
it wider or narrower and the knob to turn it, and is moved by dragging its
top edge, where the pointer shows it can be. Click a
picture, PDF page or ink to select it; drag across empty paper to select
several. Drag a corner to resize in proportion, a side to stretch that way,
and the knob above the box to rotate (hold Shift for 15° steps). A picture,
PDF page or TikZ picture in a text box is picked by a click too, with the
same handles; there a side keeps its proportions as well. Cut out of a box
and pasted on empty paper, it lies on the page by itself again.

**Lasso select** — select mode, v, or l while drawing — picks what a loop is drawn
round: handwriting stroke by stroke, so one word can be taken out of a line,
and pictures, boxes and pages whose middle it takes in. A tap picks what it
lands on; a press anywhere in the selection's box moves it. Nothing is typed
with it, and a text box is moved by its top edge only while the
type-and-select tool is in hand.

### Notebooks, pages, search

**Space p** (Ctrl+Shift+E) summons the **picker** over the page: the
notebooks, the sections of the one the cursor is on and the pages of the
section, in three columns, as a file manager has them. It opens on the page
open; j and k (or the arrows) move up and down a column, h and l go between
columns, g and G to the first and the last, z folds away the subsections or
subpages beneath a row or unfolds them, and Enter opens a page — or goes into
a notebook or a section. t opens the page in a new tab. In a column, n makes a
new notebook, section or page, N a subsection or a subpage, r renames, d
deletes, x, y and p cut, copy and paste, and Space (or a right-click) shows
everything else that can be done to the row. J and K move a notebook,
section or page down and up, as dragging it above or below another with the
mouse or a pen does. **o** orders the notebooks, the sections or the pages:
by when they were made, when they last changed or by name, either way round
— or as you arranged them; moving one in a list ordered otherwise keeps the list as it
is shown, as arranged from then on. b opens the bin, Tab turns
to the **graph** of everything, ? shows every key and Esc puts it away. It
goes once a page is picked; a new page opens with the caret in its title.
A title too long for one line goes on over more, pushing the date down.
**Space P** (Ctrl+P) finds a page by a few letters of its name.

**/** (Ctrl+F) opens the **search line**: the best match opens as it is
typed, the words found marked on the page, and the pages found are listed
beneath it, each with its words, to step through with the arrows or Tab or
to click. Enter keeps them marked, n and N go to the next and the previous
page found, and Esc forgets them.

Keys count however fast they are typed: those that come while the menu, the
picker, the search line or a new text box is still on its way are kept for
it, not lost — **i** and the words straight after it, Space held into **d e**,
**/** and what to find.

### Splitting the window

**Space w v** shows the page of another tab beside this one, and **Space w
s** beneath it — a new tab's, chosen in the picker, if there is no other.
Alt and h, j, k or l, or a click in the other page, gives it the keys. Drag
the line between them to share the window otherwise, and double-click it for
half each again; the share is remembered. **Space w q** shows one page
again, the other staying a tab.
A page is written on in one place at a time: beside itself, it is not opened
twice.

### Moving and sizing what floats

Everything that floats over the page but the status line — the menu, the
picker, the search line, the AI, the cheat sheet, the page drawn small, Go to
and Commands, the settings — is moved by dragging its top edge or its head,
and sized by dragging any edge or corner. Each opens again where it was left;
a double-click on its top edge puts it back, and **Settings → Layout → Panes**
puts back any or all of them. A menu made narrower sets its keys out in fewer
columns.

### Glass and motion

What floats over the page — the status line, the menu, the picker, the AI —
is clear liquid glass the notes show through, their colours glowing through
it, its edge catching the light. It holds still: the menu and the picker
open in the same place each time, and grow to fit more without shrinking
back as they show less. What is picked or showing is marked with a drop of
the accent — a bar beneath a tab, beside a row — rather than a tint. **Settings → Appearance** makes it
solid instead, and sets how fast things move, from off to twice as fast; the
system's setting for less motion stops it too.

## Canvas or pages

A page is one of two kinds of paper, chosen when it is made — **New page**
asks, offering what was chosen last, so Enter makes another of the same:

* **Canvas**: one paper going on to the right and down as far as you
  write, to write anywhere on: it scrolls half a window past what is on it,
  and further as you write there.
* **Pages**: sheets of A4, upright or landscape, in the middle of the window, one
  after another, as in a paper notebook or GoodNotes, each printed blank,
  lined, squared, dotted, with music staves, or for Cornell notes.

**Space z l** (Ctrl+Shift+L) switches a page between the two at
any time. Nothing on it moves: switched to pages, it is cut into sheets as
wide as its widest writing, enough of them to hold it all, a line of
handwriting across two sheets cut at the edge; switched back, it is the
canvas it was. A page shown as pages keeps its sheets while it is a canvas,
for when it is pages again.

Shown as pages, **Space s**, the sheets, adds a sheet after the
one in view (**Add sheet**, Ctrl+Shift+Enter, or the button below the last
sheet), asking what it is printed with and which way up it is turned
(**P** upright, **L** landscape) — as the sheet in view is, for Enter — so
upright and landscape sheets can follow one another; sets what the sheet in view is printed with, or every sheet
(**Paper**); moves the sheet in view up or down with what is on it (**Move
up**, **Move down**); and deletes it with what is on it (**Delete sheet**,
which Ctrl+Z puts back). Writing below the last sheet adds sheets enough
to hold it. Zoomed far out, a sheet's lines grow fainter rather than go.
The desk around the sheets is held to move them, and the pointer shows a
hand there; a pen writes only on the sheets, and a line drawn off the edge
of one stops there. **Fit page** fits the whole sheet in view.

A PDF printout asks where it goes: **on new sheets**, a sheet to each of
its pages, turned as that page is, after the one in view (on a page
shown as pages); **on this page**, over what is there — on the sheets from the one in view on, or
down a canvas; or **as a new page** of its own, shown as pages, a sheet to
each of its pages and named after the file, as for a book. On sheets of
their own, its pages are set as the sheets' background, to write over
without picking them up; **Set picture as background**, in the menu on a
right-click, takes one out of the background again.

## Dropping things on a page

Anything dragged onto a page from outside — a file manager, a browser,
another program — goes where it is let go, a label beside the pointer
saying so while it is held there:

* a picture (PNG, JPEG, WebP, BMP) as a picture, and a GIF as a picture
  that plays, even with the desktop's animations turned off; one dragged
  out of a browser is fetched from the web;
* a PDF as a printout, asking where it goes as **Insert PDF printout**
  does, the sheets from the one it is let go on;
* a LaTeX document (`.tex`) in a box, typeset as **Space i l** does, and a
  text file (`.txt`, `.md`) or text dragged by itself in a box as it reads;
* notes from OneNote, Xournal++ or another copy of this app, brought over
  as **Settings → Files → Import** brings them;
* any other file attached, shown as its name and opened with whatever
  opens it.

Several dropped together lie one under another. Let go on the text box
being typed in, they go into it at the caret.

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

**Shapes** (s in draw mode, or Space d s) holds shapes to drag out on the page: lines
and arrows; outlines; graphs — axes, in one quadrant, four or in 3D, a
number line and a grid, ticked every square of the page's grid; and solids,
their hidden edges dashed. A click puts one down at its usual size. Shift
keeps a box square and a line to steps of 15°. Shapes are drawn in the
pen's colour and width, and are ink once drawn: picked, moved, resized,
turned and erased as handwriting is.

**Settings → Pen** steadies the pen's line (Smoothing: the line trails the
pen a little, as if pulled on a string, and catches up where it lifts), sets
what the pen's two buttons do held as it touches the page — erase, select,
lasso, scroll or nothing; erase and lasso unless changed — and turns shapes on
holding still off. Pressing a button with the pen over that page shows which
one it is. A pen's other end, where it has one, always erases. Over the
page the pen, highlighter and eraser show what they would touch it with: a
dot as thick as the line, the highlighter's nib, the eraser's reach.

## Colours and fonts

**Inverted**, in the text colour's menu and standing first and tall beside
the pen's colours, is no colour of its own but the opposite of what is
beneath: black on the paper, white over a dark picture or highlight, so it
can be read on either. **Space f f**, the font, sets text in the
page's own typeface, one the app brings — which looks the same on every
computer — or any installed on this one. Text brought from OneNote in
Calibri or Consolas keeps its lines where they were on a computer without
those fonts: it is drawn in faces made to their measure, Carlito and
Inconsolata.

**Settings → Appearance → Grain** lays a fine grain over the whole window,
the pages included, as on paper or film, as strong as its slider is set:
none unless chosen.

## Keyboard

Every shortcut is listed in the app under **F1**, where the shortcuts of
commands can be changed; those of typing are fixed, as are the modes' keys,
which **?** lists.

| Keys | Does |
| --- | --- |
| Ctrl+P / Ctrl+Shift+P | Go to a page, section or notebook / run a command, by a few letters of its name |
| Alt+Up / Alt+Down | Previous / next page in the section (with Shift: section in the notebook) |
| Alt+Left / Alt+Right | Back / forward through the pages the tab has shown |
| Ctrl+N, F2 | New page, rename the page |
| Ctrl+T / Ctrl+W / Ctrl+Shift+T | New tab / close the tab / reopen the tab closed last |
| Ctrl+Tab, Alt+1–9 | Next tab, show a tab |
| Ctrl+Shift+E / Ctrl+F / Ctrl+Shift+G | The picker / the search line / the graph in the picker |
| Ctrl+J | The AI of what is showing, and back |
| Ctrl+, / Ctrl+Shift+D | Settings / light or dark |
| Space, Ctrl+Space | The menu |
| Shift+F10, Menu | The menu a right-click opens: for the text picked, or at the caret, where something is typed |
| Alt+H / J / K / L | The other page of a split window |
| Ctrl+Shift+L, Ctrl+Shift+Enter | Pages or canvas; add a sheet after the one in view |
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

Press Alt+= and type. The formula is typeset in its place as you type,
outlined, and its source is typed in a strip just beneath its line, as wide
as the box, over the text below rather than pushing it down. While the
source is not yet a formula — a bracket still open — the formula stays as it
last was and the strip says what is missing. Once the source is longer
than 80 characters, or on more than one line, it moves to a window of its
own, typeset in its place behind it all the same; it comes back beneath the
line once it is 20 shorter and on one line. **Settings → Formulas → Source
window** sets how long it grows first. In Simple syntax a comma between two
digits is a decimal comma, as in German — `2,5` — and one with a space after
it parts a list: `f(1, 2)`. Enter or Esc finishes it,
in the window too; Shift+Enter there starts a new line. Arrowing into or
clicking a formula shows its source again. Tab moves to the next place a
structure left to fill in. A formula alone on its line is typeset large;
end it with `#` to centre it. Finishing a centred formula takes the caret
on to the start of the line beneath, and text typed beside one, or a line
broken off it, is not centred.

Formulas are stored as LaTeX and can be typed in LaTeX or in the Simple
syntax, which the cheat sheet (**Space m c**) lists in full:

`x^2`, `x_i`, `a/b`, `sqrt(x)`, `root(3, x)`, `sum_(i=1)^n`, `prod`,
`int_a^b`, `lim_(x->0)`, `vec(v)` and `vec(1, 2, 3)`, `mat(1, 2; 3, 4)` (also
`bmat`, `vmat`, `matrix`), `cases(x, x>0; -x, x<0)`, `abs(x)`, `norm(v)`,
`set(1, 2)`, `binom(n, k)`, `n!`, `f'(x)`, `ket(psi)`, `bra(phi)`,
`braket(phi, H, psi)`, Greek letters by name, `oo`, `->`, `<=`, `!=`, `+-`,
`*`, `"text"`. LaTeX can be typed among it: a `\command` with its braces —
whose contents are read as Simple, `\boxed{a/b}` — environments
(`\begin{align} … \end{align}`), text and fonts (`\text{…}`, `\mathbb{R}`)
and `\left(` … `\right)` as they are, and anything in backticks.

The typesetter reads amsmath, amssymb and mathtools as notes use them:
`align`, `gather`, `equation`, `multline`, `split`, `alignat`, `cases`, the
matrices (`pmatrix*[r]` too), `\tag`, `\dfrac`, `\binom`, `\overset`,
`\xrightarrow`, `\boxed`, `\substack`, `\iint`, `\operatorname*`, and the
rest. A formula is one equation: `\tag{2}` is set after it, and labels and
numbering show nothing. `\newcommand`, `\def` and `\DeclareMathOperator`
define commands for the formula they are in.

**Settings → Formulas** holds your own preamble: commands
(`\newcommand{\Rn}{\mathbb{R}^n}`, `\DeclareMathOperator`, `\def`) and TikZ
styles (`\tikzset`) that every formula is typeset with.

A TikZ picture — `\begin{tikzpicture} … \end{tikzpicture}` or `\tikz …;` —
on a line of its own is a picture in the text, as a photo is: a click picks
it, its corners resize it, and **right-click → Edit TikZ source** opens its
source in a window, the picture drawn again as you type; Ctrl+Enter
finishes. The window is as tall as the source, and scrolls only once it
fills the screen; Ctrl+Z and Ctrl+Y undo and redo what was typed there.
Cut out of the text and pasted on the paper, it lies on the page by
itself, as a picture does, and is edited there the same way. A picture may
define its own commands — `\def`, `\newcommand` with an optional first
argument — before it uses them. A picture typed as a formula alone on its line becomes one when
it is finished; one in a line of text stays a formula, typed as LaTeX.

It is drawn as LaTeX draws it, at the size of the text around it:
`\draw`, `\fill`, `\filldraw`, `\path`, `\shade`, `\node`, `\coordinate`,
`\pic`, `\matrix`, scopes, `\foreach` and styles (`/.style`, `\tikzset`);
lines (`--`, `-|`, `|-`), curves (`.. controls ..`, `to[bend left]`,
`edge`), `rectangle`, `circle`, `ellipse`, `arc`, `grid`, `parabola`, `sin`,
`cos` and `plot` (of coordinates or a function); nodes placed on paths,
beside each other (`right=of a`) and labelled, their text typeset as LaTeX;
colours (`red!30!blue`), line widths, dashes, rounded corners, opacity,
shading, and scaling, shifting and rotating. Of TikZ's libraries:

* **arrows** and **arrows.meta**: `->`, `-stealth`, `-{Latex[open]}`,
  `*-o`, `|-{Bracket}`, `-Square`, `-Kite`.
* **calc**: `($(a)!0.5!(b)$)`, `($(a)!1cm!(b)$)`, `($(a)!0.5!90:(b)$)`,
  `($(a)!(c)!(b)$)` and sums such as `($(a) + 2*(1,0)$)`.
* **positioning**, **fit** (`fit=(a)(b)`) and **through**
  (`circle through=(b)`).
* **shapes.geometric**: `diamond`, `regular polygon`, `star`,
  `isosceles triangle`, `trapezium`, `semicircle`.
* **intersections**: `name path=a`, `name intersections={of=a and b, by=x}`.
* **angles** and **quotes**: `\pic[draw, "$\alpha$"] {angle=a--b--c}`,
  `{right angle=a--b--c}`, `edge["$x$"]`, `node["label" below]`.
* **decorations**: `zigzag`, `snake`, `coil`, `saw`, `bumps`,
  `random steps`, `brace` (and `mirror`), `ticks`, `border`, and
  `markings` with `\arrow{>}` or a `\node` along the path; `postaction`.
* **patterns**: `north east lines`, `north west lines`, `horizontal lines`,
  `vertical lines`, `grid`, `crosshatch`, `dots`, `crosshatch dots`.
* **backgrounds**: `on background layer`, `pgfonlayer`.
* **matrix**: `matrix of nodes`, `matrix of math nodes`, or `\node`s in
  cells, named `m-1-2`.
* **pgfplots**: an `axis` with `\addplot` of a function (`{x^2}`),
  `coordinates`, a `table`, or a curve (`({cos(x)}, {sin(x)})`), with
  `\closedcycle`, marks, a legend, `xlabel`, `ylabel`, `title`, `grid`,
  `xtick`, limits, and `axis lines=box`, `left` or `middle`; other TikZ in
  it is drawn in the plot's coordinates (`axis cs:`, `rel axis cs:`).

A picture is always typed as LaTeX: it has no Simple syntax.

**Space i l** takes LaTeX of any length — a passage, or a whole
document with its preamble — and puts it into the text box being typed in,
or a box of its own: paragraphs, `\section`s as headings, lists, tables,
bold, italic and links as text, `$…$` as formulas in the line, and `\[…\]`,
`$$…$$` and the display environments as formulas on lines of their own,
centred, and TikZ pictures, with the styles the document sets for them.
Commands the LaTeX defines are written out where they are used.
**Settings → Files → Import → LaTeX** (or **Import notes…** in the command
palette) does the same with `.tex` files, each a page of the section open.

A formula brought in this way stays LaTeX: it opens as LaTeX whichever
syntax is chosen, and the switch stays on LaTeX while it is open. It can
also use the packages documents use for physics, chemistry and units, which
formulas typed here cannot (they would have no Simple syntax):

- **physics** — sized brackets (`\qty(…)`, `\abs`, `\norm`, `\eval`,
  `\order`, `\comm`), vectors (`\vb`, `\va`, `\vu`, `\grad`, `\div`,
  `\curl`, `\laplacian`), derivatives (`\dd`, `\dv`, `\pdv`, `\fdv`),
  Dirac's notation (`\bra`, `\ket`, `\braket`, `\ketbra`, `\expval`,
  `\mel`), matrices (`\mqty`, `\pmqty`, `\imat`, `\dmat`, …), operators
  and `\qq{…}`, `\qif` and the other words set between quads;
- **mhchem** — `\ce{2H2 + O2 -> 2H2O}`: formulas, charges, isotopes,
  hydrates, bonds, states, arrows labelled above and below, gas and
  precipitate; and `\pu{8.314 J K-1 mol-1}`;
- **siunitx** — `\num`, `\si` and `\unit`, `\SI` and `\qty`, `\ang`, and
  the ranges and lists, units by name (`\kilo\metre\per\second\squared`,
  `\km`) or as written (`kg.m/s^2`).

## The AI

Open any page's AI (**Ctrl+J**, or **a**) and **Choose a model**. Nothing is
sent anywhere until you ask something.

The AI floats on a pane of glass down the right of the page, the notes still
in view beside it; a click on them, or Esc, goes back to them. Its overview
lists the sets to study the page by, each on its digit — **Make** one, or
open it — the questions ready to ask (**q**), and the conversations and
answers kept (**c** finds one by name; a right-click deletes or renames it).
The line to ask in is at its foot: **i** or Enter goes to it, Enter asks,
**Web** lets the answer search the web, and the model's name opens the
settings to choose another.

To have part of an answer written again, select it and choose **Write this
again…** from the menu of what is selected (a right-click, or a long press).
The paragraphs, list items or formulas the selection touches are written
again in their place, as you say — *simpler*, *with an example* — or just
better if you say nothing; the rest of the answer stays as it was, and the
conversation goes on from the answer as it now is.

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

**About you**, in the AI settings, goes with every question and study set:
your school year, your course, the exams you are working towards ("I am in
Q13 in Bavaria").

What the AI makes to study from is a list of **study profiles**: the summary,
flashcards, quiz and key terms, and any of your own. **Edit** on a profile
changes its name, what it asks for, and **Anything else** (the language, how
many, how hard), which wins where it differs from the rest; **Reset to the
original** brings one of the app's own back. **New study profile…** describes
something else to make, in the form of one of the app's own sets or as free
text: exam tasks with worked solutions, a cheat sheet, a timeline. Free text
cites your notes as answers do.

## Where notes live

Every note is a file in the notes folder that **Settings → Files** chooses:
put it in OneDrive, Dropbox or Syncthing to have your notes on every computer.
Until one is chosen they are kept in the app's data folder (on Windows,
`%APPDATA%\dev.aantekening\aantekening\workspace`). Starting the app with
`AANTEKENING_HOME=/path/to/dir` uses another folder for that session.

If the folder the notes were opened from holds none when the app starts —
a drive not plugged in, a sync not yet done — the app says so and waits:
**Try again** once they are back, or **Start new notes there** to begin
afresh in that folder. The notes open in one window at a time; a second
window says they are open in the first.

A page that cannot be saved — the disk full, say — is kept in the app's
data folder, under `index/rescued`, and put back when the app next opens,
as the page itself or beside it, marked "(rescued)".

## If something goes wrong

What went wrong is noted, with when, in `logs/errors.log` in the app's data
folder (on Linux, `~/.local/share/dev.aantekening.aantekening`; on Windows,
`%APPDATA%\dev.aantekening\aantekening`). Nothing in it leaves the computer;
it is what to attach to a report of a problem.

## If scrolling misbehaves

Run the app with `AANTEKENING_TRACE_INPUT=1` to print every pointer event as
the engine delivers it, every key, and every change of view with the code
that made it.
