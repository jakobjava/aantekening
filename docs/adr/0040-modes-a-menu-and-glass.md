# 40. Modes, a menu a key away, and glass over the page

**Status:** accepted; supersedes ADR 9, and ADR 11's ribbon and sidebar;
revises the look of ADR 18 and the tab strip of ADR 16

## Context

The window was a ribbon of tabs across the top, a tab strip beneath it, a
sidebar of panels down the left and the page in what was left: square,
still and opaque throughout (ADR 18). Every command was always in view, and
so was all of the window's furniture. Writing in it felt cold: the notes
had to share the window with the tools for them, and nothing about it
invited sitting down to work.

The person using it wants the notes left undisturbed — nothing shown that
is not asked for — and wants the app worked from the keyboard first: a
system after vim, with modes, that shows what the keys do rather than
expecting them known. They chose frosted glass for what floats over the
page, a little life in how things move, and a way to keep two pages in
view at once.

## Decision

**The window is the page.** The page fills the window; a thin rounded
line of glass all along it, the **status line**, floats clear of its top or
its foot, as chosen. It
shows the mode, the tabs, numbered, and what the page with the keys has in
hand: the pen, a save under way, the zoom. Nothing else is shown until it
is summoned. The canvas lets its top scroll out from under the status line
(`CanvasController.obscured`), so the notes run on beneath the glass.

**Modes.** What a key does depends on the mode the page is in, worked out
from what it is doing rather than kept apart from it: *insert* while a text
box has the caret, *draw* while a pen, the highlighter, a shape or the
eraser is in hand, *select* with the lasso, *AI* while the tab shows its
AI, else *normal* (`EditorMode`, `pageModeProvider`). Each has its colour,
on the status line and the ring that marks where the keys went. In normal
mode the letters are commands: h j k l go from thing to thing on the page,
by direction (`nearestTowards`), keeping to a line or a column; f labels
everything in view to jump to, as Vimium does a page's links; i types, d
draws, v selects, a asks the AI, and so on. Typing is typing: insert mode
is the text box as it was, Esc leaving it.

**One model for keys, the menu and every right-click.** A mode's keys are a
`KeyLayer` of `KeyAction`s, each running something or opening a further
layer; the menu is a layer, and so is each part of it. The **guide**
(`openKeyGuide`) shows a layer on a pane of glass in the middle of the
window, its top always at the same height (`_Middle`) — at once for the
menu (Space, Ctrl+Space while typing, or a right-click), or once the keys
pause in the middle of a sequence, as which-key does. Opened anywhere else
— beside the focus, at the pointer — it was tried, and the eye had to find
it again each time. It never shrinks while it is open (`SteadySize`), so
going from layer to layer it holds still. Its columns are as wide as their
labels, its rows close together, so a layer is taken in at a glance. It
takes the keyboard while it is open and gives it back after. Keys are read
as the characters they type (`ModeKey`), so they are the same on any
layout. Everything the ribbon held is in the menu's layers, built from the
page's commands (`PageLayers`): formatting, ink and shapes, formulas,
sheets, the view, spelling. Galleries — colours, shapes, structures — show
as tiles, each with its key. Every other right-click menu opens in the
guide too (`showCommandMenu`), each command on a letter of its name, with
the page's own layers after a text box's (`MenuExtras`). The ribbon, its
arrangement by dragging, and the sidebar's are gone: keys are changed in
the settings instead.

**Summoned, then gone.** The notebooks and pages and the graph are the
**picker**, a pane of glass called over the page (Ctrl+Shift+E, Space p)
and gone once a page is picked from it. It is three columns — notebooks,
the sections of the one the cursor is on, their pages — worked as a file
manager's are: a cursor in each, j k up and down, h l between columns,
Enter into a notebook or a section or opening a page, and a letter for
everything done to a row (new, rename, delete, cut, copy, paste, move,
order), set out in the guide on ? and along its foot (`Picker`). `/` opens
a **search line** by the status line: the page marks what is found as it
is typed, the pages found listed beneath it to step through, Enter keeps it
marked for n and N to step through, Esc forgets it. Go to and Commands are
one `Chooser`, which choosing a typeface uses as well.

**No key lost.** Keys typed from memory come faster than what they open
can be drawn. So whatever answers a key and must hear the next — the
guide, the jump labels, the picker — takes the keys straight from the
keyboard from the moment it is asked for, not once it has the focus
(`KeyCatch`): ahead of the focus (`FocusManager.addEarlyKeyEventHandler`),
so what has the focus never hears them too, and leaving alone the keys
already down as it was made, the one that made it among them. Catches
stack, the latest hearing the keys; each ends with what made it, closed or
gone with the window. The picker keeps those that come before it is drawn
for it (`PickerKeys`); what is typed for a field or a text box on its way
— after i, o, `/` or the chooser — is kept and typed into it once it is
there (`TypeAhead`). A key pressed with Space still held opens the menu and
is its first key, so Space d e is the eraser however close together.

**The AI beside the notes.** A tab's AI is no longer a view in place of
the page with a list down its side, but a pane of glass floating down the
right of the page (`AiPane`), the notes in view beside it, gone with Esc or
a click on them. Its head says whose AI it is in the AI mode's colour, with
the way back to the overview; its overview is the list that was down the
side, set out on lines — the sets to study, each on its digit, the
questions ready to ask, the conversations and answers kept — and its foot
the line to ask in, as the search line is at the window's. Every part of it
is a key away: o, the digits, i, n, c for a conversation by name (a
`Chooser`), q for a question ready to ask.

**Compact, and still.** What floats is as large as what it holds and no
larger — the picker as tall as its longest column, the menu's columns as
wide as their labels — so all of it is seen at once, and as much of the
notes as can be; but it does not shrink back while it is open, and its top
stays where it was, so going through notebooks of more or fewer pages
nothing jumps under the eye.

**Moved and sized by hand.** Every pane that floats — the menu, the
picker, the search line, the AI, the cheat sheet, the page drawn small, the
chooser, the settings — is a `FloatingPane`: moved by a strip along its top
edge or by its head (`PaneDragArea`), sized by any edge or corner, never
out of the area it floats over, and kept where it was left
(`panePlacementProvider`, a preference for each). Until it is moved or
sized it goes where, and is as large as, it goes by itself; sized by hand,
what is in it fills it — the menu then sets its keys out in as many columns
as fit. The status line alone stays where it is.

**Splits.** The window splits between the tab showing and another, side
by side or one above the other (`TabsState.beside`, `stacked`). Only one
pane has the keys: its commands are the page's, its page the status line's
(`activePageProvider`), and giving the other the keys — Alt and h j k l, or
a click — is showing its tab. Each pane's editor stays with its place, so
going between them opens nothing again. A page is never edited in two
places at once: beside itself, it is not opened twice.

**Liquid glass, soft corners, motion, one accent.** What floats is clear
liquid glass (`Glass`): a light wash of the base over the notes, blurred
and made more vivid, so their colours glow through it rather than grey —
and, so that what is written on it always reads, what lies beneath is
dimmed in the dark and lifted towards white in the light, rather than the
glass being made thicker;
within a fine rim whose edge catches the light, brightest at one corner and
glinting at the other, under a sheen across its top (`_LiquidEdge`),
casting a soft shadow drawn only outside it — or solid, as chosen. The
accent is never a tint: what is picked or showing is a little more of the
glass's light (`Tones.lift`, the pointer's `veil`), marked with a drop of
the accent at full strength (`Drop`) — a rounded bar beneath the tab
showing or the view, beside the row the keys are on; a dot for what is
open, and in the mode's own colour for the mode. Buttons that stand out are
filled with it. In the dark the accent is lightened further than the base
alone asks, as the glass over the white page is grey rather than black.
Nothing takes a slot of its own beside the page: the scrollbars float
over it as slim rounded thumbs in the accent, fuller under the hand, with
no track (`PageScrollbar`); the page drawn small, the cheat sheet and the
AI float on glass down its right. On the page, what is picked is ringed in
the accent with rounded corners, its handles drops of the accent in white
rings. A text box shows nothing of itself — no outline, no band — until it
is clicked, when it is framed as a picture is, with handles for its width
alone; the strip along its top that moves it is still there, drawn as
nothing, the pointer over it saying it moves. Settings, dialogs,
tooltips and messages, which are read and filled in, are solid raised
panels in the same rounded shape. Corners are rounded throughout as one (`Corners`): panels and cards,
controls, small marks; a note set apart is a `Callout`, a bar of colour
down its side. What floats in settles with a little give and fades as it
goes, and the focus ring glides to what the keys moved to (`Motion`,
`FocusGlide`), as fast as chosen, from off to twice as fast, and not at all
where the system asks for less motion.

## Consequences

* Nothing is in the way of the notes, and everything is still a key or a
  click away: the menu shows every key it offers, and ? shows the mode's.
* Space, held, still moves the page with the pointer; the menu opens as it
  is let go, unless it was.
* The blur beneath the status line is drawn again as the page scrolls under
  it — a strip of the window, cheap, and none at all with the glass solid.
* Glass is never faded as a whole: under a layer that fades it, what lies
  beneath it is drawn again, blurred, every frame — a pane floating in took
  up to 200 ms a frame. It fades in by itself instead (`GlassArriving`), its
  blur and colour growing with it, which costs no more than a pane at rest.
* Keys taken ahead of the focus are hidden from the window's shortcuts as
  well, which therefore stand aside while a catch is made (`CommandKeys`);
  a dialog opened from the picker takes the keys back from it while it is
  over it.
* The key caps name keys in words — Enter, Del, Bksp — as the typefaces
  bundled have no symbols for them.
* Touch and the pen reach the menu by a right-click or a long press as
  before; a way to it made for fingers is left until the app is tried on a
  phone.
