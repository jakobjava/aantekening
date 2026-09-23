# 16. Tabs, scrollbars and a map of the page

**Status:** accepted

## Context

One page was open at a time, with one sidebar choosing it, so going between
two pages being worked on together meant finding each again in the panes.
And the page, running on without end, had nothing to show how much of it
there was or where the view was on it; moving about was by wheel, trackpad
or drag alone.

## Decision

* **Tabs beneath the ribbon**, as in a browser (`TabStrip`). A tab
  (`NoteTab`) is what its sidebar has chosen — notebook, section and page —
  its open panel and its search. There is still one page editor and one
  sidebar: the providers they have always read (`selectedPageProvider`,
  `searchQueryProvider`, `sidebarProvider` and the others) now read the tab
  showing, from `tabsProvider`, and change it alone. So the sidebar acts on
  the tab showing, and nothing that used them had to change. The panel is
  built afresh for each tab, so one tab's search field and lists are not
  another's.
* **Opening, closing and moving tabs** as a browser does: Ctrl+T, Ctrl+W,
  Ctrl+Tab and Ctrl+Page Up and Down, taken from the keyboard itself since
  they must work wherever the focus is; a page opens in a new tab from its
  menu, a middle-click or Ctrl+click; a middle-click closes a tab; a tab is
  dragged along the row to move it. Closing the last tab leaves an empty
  one. The tabs are kept in the preferences, but not their searches; what a
  tab kept that has since been deleted is forgotten, in every tab, as soon as
  it is deleted and when the window opens.
* **The editor remembers each page's view** for the session, so going back to
  a tab finds its page where it was left.
* **Scrollbars** (`PageScrollbar`) down the side and along the foot of the
  page. How far a page scrolls is made up (`ScrollSpan`), since it has no
  end: from its top-left corner to half a view past its content, and never
  short of where the view is. A drag holds that extent while it lasts, so
  the thumb stays under the pointer as the page grows.
* **A map of the page** (`PageMinimap`), turned on from View → Page preview
  in place of the vertical scrollbar, as Kate and other code editors draw a
  file: the page drawn small across its width, the part in view marked,
  scrolling through a page longer than itself in step with the view. It is
  drawn by `CanvasPreview`, the canvas's own layers seen from another
  viewport, with the page's own widgets, each kept while its element is the
  same, so a change to one box draws only that box again.

## Consequences

* A page's undo history is still the editor's, and starts afresh whenever
  another page is shown, in a tab or not.
* The scrollbars and the map take room from the page rather than lying over
  it, as a desktop application's do.
