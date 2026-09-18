# 11. The window: a ribbon across it, a sidebar of panels, a page with a corner

**Status:** accepted

## Context

The window had a bar across the top holding the app's name, a wide search
field and an AI button; beneath it, fixed-width notebook and page panes, then
the page editor with the ribbon (ADR 9) over the page alone. Search results
replaced the page list while a query was typed. The panes could not be made
wider or put away, the search field took the most valuable strip of the
window for something used now and then, and a search showed where a word was
only in a snippet, never on the page.

Pages had no title of their own: the store took the first line of text as a
page's name, and nothing on the page showed it. The canvas ran on in every
direction, so a page could be scrolled, and written on, above and to the left
of where it started — somewhere OneNote pages do not go.

## Decision

* **The ribbon spans the window.** It belongs to the page editor, whose
  commands it carries, so the editor now spans the window too and lays the
  page out among whatever it is given — the sidebar — beneath the ribbon.
  The editor stays as pages are opened and closed, loading each in turn; the
  tool and pens in hand carry over from page to page. With no page open, the
  ribbon is greyed out but keeps its place and size.
* **A sidebar of panels.** A strip of buttons down the left opens a panel
  beside it: the notebooks and pages, search, the graph, the local AI.
  Clicking the open panel's button closes it. Each column of a panel is
  widened or narrowed by dragging its right edge, and the widths, the panel
  open and the buttons' arrangement are kept in the preferences. In a window
  too narrow for a panel beside the page, the panel opens over the page and
  goes once a page is picked from it, as a drawer would.
* **One way to arrange buttons.** The ribbon's buttons and the sidebar's are
  arranged the same way: an `Arrangement` of items in groups, each item in
  exactly one group, saved by an `ArrangementController` and rearranged by
  `ArrangeableItem`s dropped on `ArrangementDropTarget`s. Anything else whose
  buttons should be movable takes these three.
* **Search on the page.** The search panel opens the best match as it is
  typed, with the words found marked on the page itself, in its title and its
  text boxes, and the view on the first of them; Enter and Shift+Enter step
  through the other pages that match. The query is read by core's
  `SearchTerms`, which both builds the store's full-text query and finds the
  words on a page, so what is marked is what matched.
* **A graph of the workspace.** Notebooks, sections and pages as dots, each
  linked to what it is in, laid out by a force simulation after d3-force;
  dragging a dot pulls on the rest, and clicking one opens it.
* **A page has a title, and a corner.** A page's title and date sit at its
  top-left, on the canvas. The title is the page's name — the one in the page
  list — so renaming either renames both; it is never taken from the text.
  The date and time are when the page was created, and can be changed, as in
  OneNote. The page starts at a top-left corner, `(0, 0)`: the view never
  scrolls past it, and content is kept on the page — moved, resized or added,
  it stops at the edge. Content from before pages had edges is moved onto the
  page, once, when the page is opened.
* **Menus on everything in the panes.** A right-click, or a long press,
  gives the commands for a notebook, section or page in one order: making
  something new, then cut, copy and paste, then rename and delete. Deleting
  asks first, and takes what is inside with it: a section's subsections, a
  page's subpages.
* **A native title bar.** On Linux the window asks the compositor to draw its
  title bar — thin, and in the desktop's own style — except on GNOME, whose
  own windows have header bars; there the header bar is made compact.

## Consequences

* The page editor lays out a widget it does not know, through `around`, so
  it can be tested alone. The sidebar in turn knows nothing of editing.
* A page switched to is read before it can be edited or saved: the editor
  saves the page being left under that page's own id, and nothing typed while
  the next is being read can land in the wrong page.
* Deleted notebooks, sections and pages stay in the store and can be restored
  with what was deleted along with them, but there is no recycle bin to do it
  from yet.
* The graph compares every dot with every other at each step, which is
  comfortable for a thousand or so pages.
